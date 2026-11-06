## The part of Xlib Retro Desktop uses to manage other programs' windows:
## loaded at run time from libX11 (as Retro Nim UI's X11 driver loads it),
## on the driver's own connection (`x11Display`).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

const libX11 = "libX11.so(|.6)"

type
  Display* = pointer
  Window* = culong
  Atom* = culong
  Time* = culong
  XBool* = cint

  XAnyEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    window*: Window

  XKeyEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    window*, root*, subwindow*: Window
    time*: Time
    x*, y*, xRoot*, yRoot*: cint
    state*, keycode*: cuint
    sameScreen*: XBool

  XButtonEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    window*, root*, subwindow*: Window
    time*: Time
    x*, y*, xRoot*, yRoot*: cint
    state*, button*: cuint
    sameScreen*: XBool

  XMotionEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    window*, root*, subwindow*: Window
    time*: Time
    x*, y*, xRoot*, yRoot*: cint
    state*: cuint
    isHint*: char
    sameScreen*: XBool

  XExposeEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    window*: Window
    x*, y*, width*, height*, count*: cint

  XMapRequestEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    parent*, window*: Window

  XConfigureRequestEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    parent*, window*: Window
    x*, y*, width*, height*, borderWidth*: cint
    above*: Window
    detail*: cint
    valueMask*: culong

  XConfigureEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    event*, window*: Window
    x*, y*, width*, height*, borderWidth*: cint
    above*: Window
    overrideRedirect*: XBool

  XUnmapEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    event*, window*: Window
    fromConfigure*: XBool

  XDestroyWindowEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    event*, window*: Window

  XPropertyEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    window*: Window
    atom*: Atom
    time*: Time
    state*: cint

  XClientMessageEvent* = object
    theType*: cint
    serial*: culong
    sendEvent*: XBool
    display*: Display
    window*: Window
    messageType*: Atom
    format*: cint
    data*: array[5, clong]

  XEvent* {.union.} = object
    theType*: cint
    xany*: XAnyEvent
    xkey*: XKeyEvent
    xbutton*: XButtonEvent
    xmotion*: XMotionEvent
    xexpose*: XExposeEvent
    xmaprequest*: XMapRequestEvent
    xconfigurerequest*: XConfigureRequestEvent
    xconfigure*: XConfigureEvent
    xunmap*: XUnmapEvent
    xdestroywindow*: XDestroyWindowEvent
    xproperty*: XPropertyEvent
    xclient*: XClientMessageEvent
    pad: array[24, clong]

  XWindowAttributes* = object
    x*, y*, width*, height*, borderWidth*, depth*: cint
    visual*: pointer
    root*: Window
    class*, bitGravity*, winGravity*, backingStore*: cint
    backingPlanes*, backingPixel*: culong
    saveUnder*: XBool
    colormap*: culong
    mapInstalled*: XBool
    mapState*: cint
    allEventMasks*, yourEventMask*, doNotPropagateMask*: clong
    overrideRedirect*: XBool
    screen*: pointer

  XWindowChanges* = object
    x*, y*, width*, height*, borderWidth*: cint
    sibling*: Window
    stackMode*: cint

  XSizeHints* = object
    flags*: clong
    x*, y*, width*, height*: cint
    minWidth*, minHeight*, maxWidth*, maxHeight*: cint
    widthInc*, heightInc*: cint
    minAspect*, maxAspect*: array[2, cint]
    baseWidth*, baseHeight*, winGravity*: cint

  XSetWindowAttributes* = object
    backgroundPixmap*, backgroundPixel*, borderPixmap*, borderPixel*: culong
    bitGravity*, winGravity*, backingStore*: cint
    backingPlanes*, backingPixel*: culong
    saveUnder*: XBool
    eventMask*, doNotPropagateMask*: clong
    overrideRedirect*: XBool
    colormap*, cursor*: culong

  XErrorEvent* = object
    theType*: cint
    display*: Display
    resourceid*: culong
    serial*: culong
    errorCode*, requestCode*, minorCode*: uint8

  XErrorHandler* = proc (d: Display; e: ptr XErrorEvent): cint {.cdecl.}

  XImage* = object
    width*, height*, xoffset*, format*: cint
    data*: pointer

const
  None* = 0.Window
  CurrentTime* = 0.Time
  KeyPress* = 2.cint
  KeyRelease* = 3.cint
  ButtonPress* = 4.cint
  ButtonRelease* = 5.cint
  MotionNotify* = 6.cint
  Expose* = 12.cint
  DestroyNotify* = 17.cint
  UnmapNotify* = 18.cint
  MapNotify* = 19.cint
  MapRequest* = 20.cint
  ConfigureNotify* = 22.cint
  ConfigureRequest* = 23.cint
  PropertyNotify* = 28.cint
  ClientMessage* = 33.cint

  KeyPressMask* = 1.clong
  ButtonPressMask* = 4.clong
  ButtonReleaseMask* = 8.clong
  EnterWindowMask* = 16.clong
  PointerMotionMask* = 64.clong
  ButtonMotionMask* = 8192.clong
  ExposureMask* = 32768.clong
  StructureNotifyMask* = 131072.clong
  SubstructureNotifyMask* = 524288.clong
  SubstructureRedirectMask* = 1048576.clong
  FocusChangeMask* = 2097152.clong
  PropertyChangeMask* = 4194304.clong

  ShiftMask* = 1.cuint
  LockMask* = 2.cuint
  ControlMask* = 4.cuint
  Mod1Mask* = 8.cuint      ## Alt
  Mod2Mask* = 16.cuint     ## Num Lock (as a rule)
  Mod4Mask* = 64.cuint     ## the Windows key
  AnyModifier* = cuint(1 shl 15)
  AnyButton* = 0.cuint

  IsViewable* = 2.cint
  GrabModeSync* = 0.cint
  GrabModeAsync* = 1.cint
  ReplayPointer* = 2.cint
  RevertToPointerRoot* = 1.cint
  PointerRoot* = 1.Window
  PropModeReplace* = 0.cint
  XA_ATOM* = 4.Atom
  XA_CARDINAL* = 6.Atom
  XA_STRING* = 31.Atom
  XA_WINDOW* = 33.Atom
  XA_WM_NAME* = 39.Atom
  XA_WM_NORMAL_HINTS* = 40.Atom
  XA_WM_TRANSIENT_FOR* = 68.Atom
  ZPixmap* = 2.cint
  CWOverrideRedirect* = culong(1 shl 9)
  CWX* = 1.culong
  CWY* = 2.culong
  CWWidth* = 4.culong
  CWHeight* = 8.culong
  CWBorderWidth* = 16.culong
  CWSibling* = 32.culong
  CWStackMode* = 64.culong
  Above* = 0.cint
  Below* = 1.cint
  PMinSize* = 16.clong
  PMaxSize* = 32.clong
  XK_Tab* = 0xff09.culong
  XK_Return* = 0xff0d.culong
  XK_Up* = 0xff52.culong
  XK_Down* = 0xff54.culong
  XK_Escape* = 0xff1b.culong
  XK_F4* = 0xffc1.culong
  XK_Super_L* = 0xffeb.culong

{.push cdecl, dynlib: libX11, importc.}
proc XOpenDisplay*(name: cstring): Display
proc XGrabKeyboard*(d: Display; w: Window; ownerEvents: XBool; pointerMode, keyboardMode: cint;
                    time: Time): cint
proc XUngrabKeyboard*(d: Display; time: Time): cint
proc XCloseDisplay*(d: Display): cint
proc XSelectInput*(d: Display; w: Window; mask: clong): cint
proc XQueryTree*(d: Display; w: Window; root, parent: ptr Window; children: ptr ptr UncheckedArray[Window];
                 n: ptr cuint): cint
proc XGetWindowAttributes*(d: Display; w: Window; a: ptr XWindowAttributes): cint
proc XCreateSimpleWindow*(d: Display; parent: Window; x, y: cint; w, h, border: cuint;
                          borderPixel, background: culong): Window
proc XChangeWindowAttributes*(d: Display; w: Window; mask: culong; a: ptr XSetWindowAttributes): cint
proc XReparentWindow*(d: Display; w, parent: Window; x, y: cint): cint
proc XMapWindow*(d: Display; w: Window): cint
proc XUnmapWindow*(d: Display; w: Window): cint
proc XDestroyWindow*(d: Display; w: Window): cint
proc XMoveWindow*(d: Display; w: Window; x, y: cint): cint
proc XResizeWindow*(d: Display; w: Window; width, height: cuint): cint
proc XMoveResizeWindow*(d: Display; w: Window; x, y: cint; width, height: cuint): cint
proc XRaiseWindow*(d: Display; w: Window): cint
proc XLowerWindow*(d: Display; w: Window): cint
proc XConfigureWindow*(d: Display; w: Window; mask: cuint; c: ptr XWindowChanges): cint
proc XSetWindowBorderWidth*(d: Display; w: Window; width: cuint): cint
proc XSetInputFocus*(d: Display; w: Window; revert: cint; time: Time): cint
proc XAddToSaveSet*(d: Display; w: Window): cint
proc XRemoveFromSaveSet*(d: Display; w: Window): cint
proc XKillClient*(d: Display; resource: culong): cint
proc XSendEvent*(d: Display; w: Window; propagate: XBool; mask: clong; e: ptr XEvent): cint
proc XInternAtom*(d: Display; name: cstring; onlyIfExists: XBool): Atom
proc XGetWindowProperty*(d: Display; w: Window; prop: Atom; offset, length: clong; delete: XBool;
                         reqType: Atom; actualType: ptr Atom; actualFormat: ptr cint;
                         nitems, after: ptr culong; data: ptr pointer): cint
proc XChangeProperty*(d: Display; w: Window; prop, kind: Atom; format, mode: cint;
                      data: pointer; n: cint): cint
proc XDeleteProperty*(d: Display; w: Window; prop: Atom): cint
proc XFree*(p: pointer): cint
proc XGetWMNormalHints*(d: Display; w: Window; hints: ptr XSizeHints; supplied: ptr clong): cint
proc XGrabPointer*(d: Display; w: Window; ownerEvents: XBool; mask: cuint; pointerMode, keyboardMode: cint;
                   confineTo: Window; cursor: culong; time: Time): cint
proc XUngrabPointer*(d: Display; time: Time): cint
proc XGrabButton*(d: Display; button, modifiers: cuint; w: Window; ownerEvents: XBool; mask: cuint;
                  pointerMode, keyboardMode: cint; confineTo: Window; cursor: culong): cint
proc XUngrabButton*(d: Display; button, modifiers: cuint; w: Window): cint
proc XAllowEvents*(d: Display; mode: cint; time: Time): cint
proc XGrabKey*(d: Display; keycode: cint; modifiers: cuint; w: Window; ownerEvents: XBool;
               pointerMode, keyboardMode: cint): cint
proc XKeysymToKeycode*(d: Display; keysym: culong): uint8
proc XLookupKeysym*(e: ptr XKeyEvent; index: cint): culong
proc XQueryPointer*(d: Display; w: Window; root, child: ptr Window; rx, ry, wx, wy: ptr cint;
                    mask: ptr cuint): XBool
proc XSync*(d: Display; discard_events: XBool): cint
proc XFlush*(d: Display): cint
proc XSetErrorHandler*(h: XErrorHandler): XErrorHandler
proc XDefaultScreen*(d: Display): cint
proc XRootWindow*(d: Display; screen: cint): Window
proc XDisplayWidth*(d: Display; screen: cint): cint
proc XDisplayHeight*(d: Display; screen: cint): cint
proc XDefaultVisual*(d: Display; screen: cint): pointer
proc XDefaultDepth*(d: Display; screen: cint): cint
proc XDefaultGC*(d: Display; screen: cint): pointer
proc XCreateGC*(d: Display; w: Window; mask: culong; values: pointer): pointer
proc XFreeGC*(d: Display; gc: pointer): cint
proc XSetForeground*(d: Display; gc: pointer; color: culong): cint
proc XFillRectangle*(d: Display; w: Window; gc: pointer; x, y: cint; width, height: cuint): cint
proc XCreateImage*(d: Display; visual: pointer; depth: cuint; format, offset: cint; data: pointer;
                   width, height: cuint; pad, bytesPerLine: cint): ptr XImage
proc XPutImage*(d: Display; w: Window; gc: pointer; img: ptr XImage; sx, sy, dx, dy: cint;
                width, height: cuint): cint
proc XSetWindowBackground*(d: Display; w: Window; pixel: culong): cint
proc XClearWindow*(d: Display; w: Window): cint
proc XClearArea*(d: Display; w: Window; x, y: cint; width, height: cuint; exposures: XBool): cint
proc XCreateFontCursor*(d: Display; shape: cuint): culong
proc XDefineCursor*(d: Display; w: Window; cursor: culong): cint
proc XSetSelectionOwner*(d: Display; selection: Atom; owner: Window; time: Time): cint
proc XGetSelectionOwner*(d: Display; selection: Atom): Window
proc XStoreName*(d: Display; w: Window; name: cstring): cint
{.pop.}

proc atom*(d: Display; name: string): Atom = XInternAtom(d, name.cstring, 0)
  ## The atom called `name` (made when there is none).

proc propBytes*(d: Display; w: Window; prop, kind: Atom; maxLongs = 1 shl 20):
    tuple[ok: bool; format: int; n: int; data: string] =
  ## A property's raw contents (`kind` 0: any type): its format (8, 16 or
  ## 32: then each item is a C long), the number of items, the bytes.
  var actualType: Atom
  var actualFormat: cint
  var n, after: culong
  var data: pointer
  if XGetWindowProperty(d, w, prop, 0, clong(maxLongs), 0, kind, addr actualType, addr actualFormat,
                        addr n, addr after, addr data) != 0 or data == nil:
    return
  let itemSize = case actualFormat
                 of 8: 1
                 of 16: 2
                 of 32: sizeof(clong)
                 else: 0
  if itemSize > 0 and n > 0:
    result.data = newString(int(n) * itemSize)
    copyMem(addr result.data[0], data, result.data.len)
  result.ok = actualType != 0
  result.format = actualFormat
  result.n = int(n)
  discard XFree(data)

proc propLongs*(d: Display; w: Window; prop, kind: Atom): seq[clong] =
  ## A 32-bit property's items (windows, atoms, numbers).
  let p = propBytes(d, w, prop, kind)
  if p.ok and p.format == 32:
    result = newSeq[clong](p.n)
    if p.n > 0: copyMem(addr result[0], unsafeAddr p.data[0], p.n * sizeof(clong))

proc propText*(d: Display; w: Window; prop: Atom): string =
  ## A text property (UTF8_STRING or STRING) as UTF-8 (STRING is Latin-1).
  let p = propBytes(d, w, prop, 0, 4096)
  if p.ok and p.format == 8:
    result = p.data
    if result.len > 0 and result[^1] == '\0': result.setLen(result.len - 1)

proc setLongs*(d: Display; w: Window; prop, kind: Atom; values: openArray[clong]) =
  ## Sets a 32-bit property to `values`.
  var v = @values
  discard XChangeProperty(d, w, prop, kind, 32, PropModeReplace,
                          (if v.len > 0: addr v[0] else: nil), cint(v.len))

proc setText*(d: Display; w: Window; prop, kind: Atom; text: string) =
  ## Sets a text property (`kind`: UTF8_STRING, STRING).
  var t = text
  discard XChangeProperty(d, w, prop, kind, 8, PropModeReplace,
                          (if t.len > 0: addr t[0] else: nil), cint(t.len))

# ---- errors that are no error ---------------------------------------------------------------------

var xTrapped*: bool
  ## an X error came while `trapErrors` ran

proc xTrap(d: Display; e: ptr XErrorEvent): cint {.cdecl.} =
  xTrapped = true
  0

template trapErrors*(d: Display; body: untyped) =
  ## Runs `body` with X errors caught instead of ending the program (Xlib's
  ## own handler exits): asking about a window that is gone -- one that
  ## closed a moment ago, the check window of a desktop that ended -- is not
  ## a reason to stop. `xTrapped` says whether one came.
  let oldHandler = XSetErrorHandler(xTrap)
  xTrapped = false
  body
  discard XSync(d, 0)
  discard XSetErrorHandler(oldHandler)
