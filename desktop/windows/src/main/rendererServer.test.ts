import { describe, expect, it } from 'vitest'
import { PREFERRED_PORT, rendererPortCandidates } from './rendererServer'

describe('rendererPortCandidates', () => {
  it('keeps the production renderer on the one origin that owns persisted auth', () => {
    expect(rendererPortCandidates(false)).toEqual([PREFERRED_PORT])
  })

  it('allows isolated development profiles to opt into fallback ports', () => {
    expect(rendererPortCandidates(true)).toEqual([
      5179, 5180, 5181, 5182, 5183, 5184, 5185, 5186, 5187, 5188
    ])
  })
})
