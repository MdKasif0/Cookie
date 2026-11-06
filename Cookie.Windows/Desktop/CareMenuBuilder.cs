using System;
using System.Windows.Controls;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Rendering;

namespace Cookie.Windows.Desktop;

/// <summary>The Feed and Toys submenus, shared by the tray icon and Cookie's own right-click menu.</summary>
public static class CareMenuBuilder
{
    public static void AddItems(ContextMenu menu, CookieBehaviorController behavior)
    {
        var feedMenu = new MenuItem { Header = "Feed Cookie", Icon = CookieIcons.MenuIcon("item-food-fish") };
        foreach (var food in Enum.GetValues<FoodKind>())
        {
            var item = new MenuItem { Header = food.GetDisplayName(), Icon = CookieIcons.MenuIcon(food.IconName()) };
            var captured = food;
            item.Click += (s, e) => behavior.OfferFood(captured);
            feedMenu.Items.Add(item);
        }
        menu.Items.Add(feedMenu);

        var toysMenu = new MenuItem { Header = "Toys", Icon = CookieIcons.MenuIcon("item-ball") };
        foreach (var toy in Enum.GetValues<ToyKind>())
        {
            var item = new MenuItem { Header = toy.GetDisplayName(), Icon = CookieIcons.MenuIcon(toy.IconName()) };
            var captured = toy;
            item.Click += (s, e) => behavior.OfferToy(captured);
            toysMenu.Items.Add(item);
        }

        if (behavior.CurrentWorldItem != null)
        {
            toysMenu.Items.Add(new Separator());
            var clearItem = new MenuItem { Header = "Put Toys Away", Icon = CookieIcons.MenuIcon("item-box") };
            clearItem.Click += (s, e) => behavior.ClearWorldItem();
            toysMenu.Items.Add(clearItem);
        }
        menu.Items.Add(toysMenu);
    }
}
