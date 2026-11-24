// Prints the real state of a window, as key=value lines, so tests can check what cmdow did
// without trusting cmdow's own output. Usage: probe "caption"
#define _WIN32_WINNT 0x0501
#include <windows.h>
#include <stdio.h>

int main(int argc, char *argv[])
{
	HWND hwnd;
	RECT r;
	MONITORINFO mi;
	LONG exstyles;
	BYTE alpha = 255;
	DWORD flags = 0;
	COLORREF key = 0;
	int layered;

	if(argc != 2) {
		fprintf(stderr, "usage: probe caption\n");
		return 2;
	}

	hwnd = FindWindowA(NULL, argv[1]);
	if(!hwnd) {
		printf("found=0\n");
		return 1;
	}

	GetWindowRect(hwnd, &r);
	exstyles = GetWindowLong(hwnd, GWL_EXSTYLE);
	layered = (exstyles & WS_EX_LAYERED) ? 1 : 0;
	if(layered) GetLayeredWindowAttributes(hwnd, &key, &alpha, &flags);

	ZeroMemory(&mi, sizeof mi);
	mi.cbSize = sizeof mi;
	GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &mi);

	printf("found=1\n");
	printf("layered=%d\n", layered);
	printf("alpha=%d\n", (int) alpha);
	printf("minimized=%d\n", IsIconic(hwnd) ? 1 : 0);
	printf("left=%ld\ntop=%ld\nright=%ld\nbottom=%ld\n", r.left, r.top, r.right, r.bottom);
	printf("work_left=%ld\nwork_top=%ld\nwork_right=%ld\nwork_bottom=%ld\n",
		   mi.rcWork.left, mi.rcWork.top, mi.rcWork.right, mi.rcWork.bottom);
	return 0;
}
