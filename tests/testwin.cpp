// Test window for the CI tests: a plain visible top level window that cmdow can act on.
// It closes itself after three minutes, so it can never outlive a CI job.
#include <windows.h>

static LRESULT CALLBACK Proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
	if(msg == WM_TIMER) {
		DestroyWindow(hwnd);
		return 0;
	}
	if(msg == WM_DESTROY) {
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProcA(hwnd, msg, wparam, lparam);
}

int main()
{
	HINSTANCE inst = GetModuleHandle(NULL);
	WNDCLASSA wc;
	HWND hwnd;
	MSG msg;

	ZeroMemory(&wc, sizeof wc);
	wc.lpfnWndProc = Proc;
	wc.hInstance = inst;
	wc.lpszClassName = "CmdowTestWindow";
	wc.hbrBackground = (HBRUSH) (COLOR_WINDOW + 1);
	wc.hCursor = LoadCursor(NULL, IDC_ARROW);
	RegisterClassA(&wc);

	hwnd = CreateWindowA("CmdowTestWindow", "cmdow-test-window", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
						 100, 100, 640, 480, NULL, NULL, inst, NULL);
	if(!hwnd) return 1;

	SetTimer(hwnd, 1, 180000, NULL);
	while(GetMessage(&msg, NULL, 0, 0) > 0) {
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}
	return 0;
}
