import { describe, expect, it, vi } from 'vitest'
import {
  focusPrimaryWindow,
  registerSingleInstance,
  type FocusableWindow,
  type SingleInstanceApp
} from './singleInstance'

function windowDouble(options: { destroyed?: boolean; minimized?: boolean } = {}): FocusableWindow {
  return {
    isDestroyed: vi.fn(() => options.destroyed ?? false),
    isMinimized: vi.fn(() => options.minimized ?? false),
    restore: vi.fn(),
    show: vi.fn(),
    focus: vi.fn()
  }
}

describe('focusPrimaryWindow', () => {
  it('reports that a primary window is not ready yet', () => {
    expect(focusPrimaryWindow(null)).toBe(false)
  })

  it('does not touch a destroyed window', () => {
    const window = windowDouble({ destroyed: true })

    expect(focusPrimaryWindow(window)).toBe(false)
    expect(window.show).not.toHaveBeenCalled()
    expect(window.focus).not.toHaveBeenCalled()
  })

  it('restores, shows, and focuses a minimized primary window', () => {
    const window = windowDouble({ minimized: true })

    expect(focusPrimaryWindow(window)).toBe(true)
    expect(window.restore).toHaveBeenCalledOnce()
    expect(window.show).toHaveBeenCalledOnce()
    expect(window.focus).toHaveBeenCalledOnce()
  })

  it('shows and focuses an existing visible window without restoring it', () => {
    const window = windowDouble()

    expect(focusPrimaryWindow(window)).toBe(true)
    expect(window.restore).not.toHaveBeenCalled()
    expect(window.show).toHaveBeenCalledOnce()
    expect(window.focus).toHaveBeenCalledOnce()
  })
})

describe('registerSingleInstance', () => {
  function appDouble(acquired: boolean): {
    app: SingleInstanceApp
    quit: ReturnType<typeof vi.fn>
    on: ReturnType<typeof vi.fn>
  } {
    const quit = vi.fn()
    const on = vi.fn()
    return {
      app: { requestSingleInstanceLock: vi.fn(() => acquired), quit, on },
      quit,
      on
    }
  }

  it('quits a secondary process before it can open another renderer origin', () => {
    const { app, quit, on } = appDouble(false)

    expect(registerSingleInstance(app, () => null, vi.fn())).toBe(false)
    expect(quit).toHaveBeenCalledOnce()
    expect(on).not.toHaveBeenCalled()
  })

  it('routes a later launch to the existing primary window', () => {
    const { app, quit, on } = appDouble(true)
    const primaryWindow = windowDouble({ minimized: true })
    const notReady = vi.fn()

    expect(registerSingleInstance(app, () => primaryWindow, notReady)).toBe(true)
    expect(quit).not.toHaveBeenCalled()
    const listener = on.mock.calls[0]?.[1] as (() => void) | undefined
    expect(listener).toBeTypeOf('function')
    listener?.()
    expect(primaryWindow.restore).toHaveBeenCalledOnce()
    expect(primaryWindow.show).toHaveBeenCalledOnce()
    expect(primaryWindow.focus).toHaveBeenCalledOnce()
    expect(notReady).not.toHaveBeenCalled()
  })

  it('defers focus when the primary window has not been created yet', () => {
    const { app, on } = appDouble(true)
    const notReady = vi.fn()

    registerSingleInstance(app, () => null, notReady)
    const listener = on.mock.calls[0]?.[1] as (() => void) | undefined
    listener?.()

    expect(notReady).toHaveBeenCalledOnce()
  })

  it('lets isolated benchmark harnesses opt out of the production lock', () => {
    const { app, quit, on } = appDouble(false)

    expect(registerSingleInstance(app, () => null, vi.fn(), true)).toBe(true)
    expect(app.requestSingleInstanceLock).not.toHaveBeenCalled()
    expect(quit).not.toHaveBeenCalled()
    expect(on).not.toHaveBeenCalled()
  })
})
