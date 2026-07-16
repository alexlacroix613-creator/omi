export type FocusableWindow = {
  isDestroyed: () => boolean
  isMinimized: () => boolean
  restore: () => void
  show: () => void
  focus: () => void
}

export type SingleInstanceApp = {
  requestSingleInstanceLock: () => boolean
  quit: () => void
  on: (event: 'second-instance', listener: () => void) => void
}

/** Restore and focus the one primary app window for a second launch. */
export function focusPrimaryWindow(window: FocusableWindow | null): boolean {
  if (!window || window.isDestroyed()) return false
  if (window.isMinimized()) window.restore()
  window.show()
  window.focus()
  return true
}

/**
 * Claim one Electron process for a userData profile and route later launches to
 * its primary window. Returns false only in the secondary process.
 */
export function registerSingleInstance(
  app: SingleInstanceApp,
  getPrimaryWindow: () => FocusableWindow | null,
  onWindowNotReady: () => void,
  bypass = false
): boolean {
  if (bypass) return true

  const acquired = app.requestSingleInstanceLock()
  if (!acquired) {
    app.quit()
    return false
  }

  app.on('second-instance', () => {
    if (!focusPrimaryWindow(getPrimaryWindow())) onWindowNotReady()
  })
  return true
}
