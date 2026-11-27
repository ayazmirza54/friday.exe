# Friday's hands: replays a JSON list of low-level input ops (from control.js) with SendInput.
# Reads the ops from stdin so nothing the model typed is ever parsed by a shell.
$ErrorActionPreference = 'Stop'
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class FridayInput {
	[StructLayout(LayoutKind.Sequential)] struct MI { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
	[StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
	[StructLayout(LayoutKind.Explicit)] struct U { [FieldOffset(0)] public MI m; [FieldOffset(0)] public KI k; }
	struct INPUT { public uint type; public U u; }
	[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
	[DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
	[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
	[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
	static void Send(INPUT i) { SendInput(1, new[] { i }, Marshal.SizeOf(typeof(INPUT))); }
	public static void Mouse(uint flags, int data) { var i = new INPUT { type = 0 }; i.u.m.flags = flags; i.u.m.data = (uint)data; Send(i); }
	public static void Key(ushort vk, bool down) {
		var i = new INPUT { type = 1 }; i.u.k.vk = vk;
		uint ext = (vk >= 0x21 && vk <= 0x2E) || vk == 0x5B ? 1u : 0u; // arrows, Home/End, PgUp/PgDn, Ins/Del, Win
		i.u.k.flags = ext | (down ? 0u : 2u); Send(i);
	}
	public static void Char(ushort c) {
		var i = new INPUT { type = 1 }; i.u.k.scan = c; i.u.k.flags = 4; Send(i);
		i.u.k.flags = 6; Send(i);
	}
}
'@
[void][FridayInput]::SetProcessDPIAware() # coordinates are physical pixels
$buttons = @{ left = @(0x2, 0x4); right = @(0x8, 0x10); middle = @(0x20, 0x40) }
$ops = [Console]::In.ReadToEnd() | ConvertFrom-Json
foreach ($op in $ops) {
	switch ($op.t) {
		'move' { [void][FridayInput]::SetCursorPos([int]$op.x, [int]$op.y) }
		'btn' { [FridayInput]::Mouse($buttons[$op.b][$(if ($op.down) { 0 } else { 1 })], 0) }
		'wheel' { [FridayInput]::Mouse($(if ($op.h) { 0x1000 } else { 0x800 }), [int]$op.d) }
		'vk' { [FridayInput]::Key([uint16]$op.k, [bool]$op.down) }
		'char' { [FridayInput]::Char([uint16]$op.c) }
		'sleep' { Start-Sleep -Milliseconds ([int]$op.ms) }
		'pos' { $p = New-Object FridayInput+POINT; [void][FridayInput]::GetCursorPos([ref]$p); Write-Output "$($p.X),$($p.Y)" }
	}
	Start-Sleep -Milliseconds 8 # let the target app keep up
}
