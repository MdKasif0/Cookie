using System;
using System.Linq;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Windows;
using Xunit;

namespace Cookie.Windows.Tests;

public class WindowNavigationAndDiscoveryTests
{
    [Fact]
    public void WindowEdgePath_CalculatesCorrectLengthAndInterpolation()
    {
        var start = new CorePoint(100, 200);
        var end = new CorePoint(500, 200);
        var bounds = new CoreRect(100, 200, 400, 300);

        var path = new WindowEdgePath(
            "test-edge",
            new IntPtr(1234),
            "TestApp",
            WindowEdgeType.TopHorizontal,
            start,
            end,
            bounds,
            FootOffset: 14.0);

        Assert.Equal(400.0, path.Length);

        // At progress 0.0 -> StartPoint
        Assert.Equal(start, path.PointAt(0.0));

        // At progress 1.0 -> EndPoint
        Assert.Equal(end, path.PointAt(1.0));

        // At progress 0.5 -> MidPoint (300, 200)
        var mid = path.PointAt(0.5);
        Assert.Equal(300.0, mid.X);
        Assert.Equal(200.0, mid.Y);

        // Closest point query
        var (closest, progress) = path.ClosestPoint(new CorePoint(250, 250));
        Assert.Equal(250.0, closest.X);
        Assert.Equal(200.0, closest.Y);
        Assert.Equal(0.375, progress, precision: 3);
    }

    [Fact]
    public void WindowNavGraph_AddsAndRetrievesNodesAndEdges()
    {
        var graph = new WindowNavGraph();

        var node1 = new WindowNavNode("n1", new CorePoint(100, 100), new IntPtr(10), IsCorner: true, new[] { WindowEdgeType.TopHorizontal, WindowEdgeType.LeftVertical });
        var node2 = new WindowNavNode("n2", new CorePoint(400, 100), new IntPtr(10), IsCorner: true, new[] { WindowEdgeType.TopHorizontal, WindowEdgeType.RightVertical });

        graph.AddNode(node1);
        graph.AddNode(node2);

        var path = new WindowEdgePath("p1", new IntPtr(10), "App", WindowEdgeType.TopHorizontal, node1.Point, node2.Point, new CoreRect(100, 100, 300, 200));
        var edge = new WindowNavEdge("e1", "n1", "n2", WindowEdgeType.TopHorizontal, path);

        graph.AddEdge(edge);

        Assert.Equal(2, graph.Nodes.Count);
        Assert.Single(graph.Edges);

        var outgoing = graph.GetOutgoingEdges("n1");
        Assert.Single(outgoing);
        Assert.Equal("n2", outgoing[0].ToNodeId);

        var emptyOutgoing = graph.GetOutgoingEdges("n2");
        Assert.Empty(emptyOutgoing);
    }

    [Fact]
    public void JumpPlanner_ExtractJumpSurfaces_GeneratesValidSurfaces()
    {
        var planner = new JumpPlanner();

        var win1 = new ObservableWindow(
            new IntPtr(101),
            "Editor",
            "Code",
            123,
            new CoreRect(200, 300, 600, 400),
            IsOccluded: false);

        // Occluded window should be skipped
        var win2 = new ObservableWindow(
            new IntPtr(102),
            "BackgroundWin",
            "Notes",
            456,
            new CoreRect(900, 300, 500, 400),
            IsOccluded: true);

        var workArea = new CoreRect(0, 0, 1920, 1040);
        var taskbarSurface = new CoreRect(80, 980, 1760, 50);

        var surfaces = planner.ExtractJumpSurfaces(new[] { win1, win2 }, workArea, taskbarSurface);

        // Win1 should produce: top landing, tl corner, tr corner
        var win1Surfaces = surfaces.Where(s => s.WindowHandle == win1.Handle).ToList();
        Assert.Equal(3, win1Surfaces.Count);

        // Win2 should produce 0 surfaces (occluded)
        var win2Surfaces = surfaces.Where(s => s.WindowHandle == win2.Handle).ToList();
        Assert.Empty(win2Surfaces);

        // Desktop ground and taskbar surface should exist
        Assert.Contains(surfaces, s => s.SurfaceKind == JumpSurfaceKind.DesktopGround);
        Assert.Contains(surfaces, s => s.SurfaceKind == JumpSurfaceKind.TaskbarEdge);
    }
}
