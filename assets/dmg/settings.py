# dmgbuild settings for Bol's DMG: release.sh runs
#   dmgbuild -s assets/dmg/settings.py -D app=build/Bol.app -D background=assets/dmg/background.tiff \
#     Bol build/Bol-x.y.z.dmg
# The window shows Bol and an Applications link on background.tiff (made by render-background.sh), with
# nothing else in the way: no toolbar, sidebar, path or status bar.
import os.path

app = defines["app"]  # noqa: F821 (provided by dmgbuild)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "bol.icns")  # the disk's own icon

background = defines["background"]  # noqa: F821
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

arrange_by = None
grid_spacing = 100
label_pos = "bottom"
icon_size = 128
text_size = 13
# Centred on the wells drawn in background.html.
icon_locations = {
    os.path.basename(app): (170, 215),
    "Applications": (490, 215),
}
