using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Desktop;

namespace Cookie.Windows.Core.Windows;

/// <summary>
/// Type of navigable edge on a window perimeter.
/// </summary>
public enum WindowEdgeType
{
    TopHorizontal,
    LeftVertical,
    RightVertical,
    BottomHorizontal
}

public static class WindowEdgeTypeExtensions
{
    public static bool IsHorizontal(this WindowEdgeType type) =>
        type is WindowEdgeType.TopHorizontal or WindowEdgeType.BottomHorizontal;

    public static bool IsVertical(this WindowEdgeType type) =>
        type is WindowEdgeType.LeftVertical or WindowEdgeType.RightVertical;
}

/// <summary>
/// Navigable edge corridor along which Cookie can walk or climb.
/// Coordinates are in WPF Device-Independent Pixels (DIPs).
/// </summary>
public record WindowEdgePath(
    string Id,
    IntPtr WindowHandle,
    string OwnerName,
    WindowEdgeType EdgeType,
    CorePoint StartPoint,
    CorePoint EndPoint,
    CoreRect WindowBounds,
    double FootOffset = 14.0,
    bool IsTraversable = true)
{
    /// <summary>
    /// Total length of this path segment in DIPs.
    /// </summary>
    public double Length => StartPoint.DistanceTo(EndPoint);

    /// <summary>
    /// Evaluates a point along this path at parametric progress t in [0.0, 1.0].
    /// </summary>
    public CorePoint PointAt(double progress)
    {
        double t = Math.Clamp(progress, 0.0, 1.0);
        double x = StartPoint.X + (EndPoint.X - StartPoint.X) * t;
        double y = StartPoint.Y + (EndPoint.Y - StartPoint.Y) * t;
        return new CorePoint(x, y);
    }

    /// <summary>
    /// Finds the closest point and normalized progress parameter along this edge path to a query point.
    /// </summary>
    public (CorePoint point, double progress) ClosestPoint(CorePoint queryPoint)
    {
        double len = Length;
        if (len <= 0.001)
        {
            return (StartPoint, 0.0);
        }

        double dx = EndPoint.X - StartPoint.X;
        double dy = EndPoint.Y - StartPoint.Y;
        double u = ((queryPoint.X - StartPoint.X) * dx + (queryPoint.Y - StartPoint.Y) * dy) / (len * len);
        double t = Math.Clamp(u, 0.0, 1.0);
        return (PointAt(t), t);
    }
}

/// <summary>
/// Node in Cookie's lightweight desktop navigation graph.
/// </summary>
public record WindowNavNode(
    string Id,
    CorePoint Point,
    IntPtr? WindowHandle = null,
    bool IsCorner = false,
    IReadOnlyList<WindowEdgeType>? CornerEdgeTypes = null)
{
    public IReadOnlyList<WindowEdgeType> CornerEdgeTypes { get; init; } = CornerEdgeTypes ?? Array.Empty<WindowEdgeType>();
}

/// <summary>
/// Directed edge in Cookie's lightweight desktop navigation graph.
/// </summary>
public record WindowNavEdge(
    string Id,
    string FromNodeId,
    string ToNodeId,
    WindowEdgeType EdgeType,
    WindowEdgePath Path,
    bool IsJump = false);

/// <summary>
/// Lightweight navigation graph representing accessible window perimeters and desktop transitions.
/// </summary>
public class WindowNavGraph
{
    private readonly Dictionary<string, WindowNavNode> _nodes = new();
    private readonly List<WindowNavEdge> _edges = new();

    public IReadOnlyDictionary<string, WindowNavNode> Nodes => _nodes;
    public IReadOnlyList<WindowNavEdge> Edges => _edges;

    public void AddNode(WindowNavNode node)
    {
        _nodes[node.Id] = node;
    }

    public void AddEdge(WindowNavEdge edge)
    {
        _edges.Add(edge);
    }

    public WindowNavNode? GetNode(string id)
    {
        _nodes.TryGetValue(id, out var node);
        return node;
    }

    public List<WindowNavEdge> GetOutgoingEdges(string nodeId)
    {
        return _edges.Where(e => e.FromNodeId == nodeId).ToList();
    }

    public void Clear()
    {
        _nodes.Clear();
        _edges.Clear();
    }
}

/// <summary>
/// State machine tracking Cookie's active window exploration and jumping phases.
/// </summary>
public enum WindowExplorationPhase
{
    /// <summary>
    /// Not currently exploring any window.
    /// </summary>
    Idle,
    /// <summary>
    /// Anticipation pause: observing the target window edge curiously before approaching.
    /// </summary>
    Anticipating,
    /// <summary>
    /// Walking toward the selected access point on the window.
    /// </summary>
    Approaching,
    /// <summary>
    /// Walking along the top horizontal edge.
    /// </summary>
    WalkingTopEdge,
    /// <summary>
    /// Transitioning around a corner with orientation adjustment.
    /// </summary>
    CornerTransition,
    /// <summary>
    /// Simulated climb along a vertical edge (when enabled).
    /// </summary>
    ClimbingVerticalEdge,
    /// <summary>
    /// Brief observation pause on the edge or corner.
    /// </summary>
    Pausing,
    /// <summary>
    /// Preparing to launch a jump: crouch anticipation, orientation alignment, target re-verification.
    /// </summary>
    PreparingJump,
    /// <summary>
    /// Airborne along a parabolic jump trajectory.
    /// </summary>
    Jumping,
    /// <summary>
    /// Touchdown landing absorption and surface stabilization.
    /// </summary>
    Landing,
    /// <summary>
    /// Concluding exploration and safely returning to desktop ground.
    /// </summary>
    Departing
}
