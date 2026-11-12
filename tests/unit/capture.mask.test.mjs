import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { maskSecrets, MASK } from '../../web/e2e/sim/helpers/mask.mjs'

const { chromium } = createRequire(new URL('../../web/package.json', import.meta.url))('@playwright/test')

test('maskSecrets remplace mots de passe et jetons, laisse les autres champs', async () => {
  const browser = await chromium.launch()
  try {
    const page = await browser.newPage()
    await page.setContent(`<input id=a type=password value="MotDePasse123"><input id=b name=access_token value="eyJabc.def.ghi">
      <input id=c autocomplete=one-time-code value="123456"><input id=d value="Diallo">`)
    assert.equal(await maskSecrets(page), 3)
    const v = (id) => page.$eval(`#${id}`, (e) => e.value)
    assert.equal(await v('a'), MASK)
    assert.equal(await v('b'), MASK)
    assert.equal(await v('c'), MASK)
    assert.equal(await v('d'), 'Diallo')
  } finally { await browser.close() }
})
