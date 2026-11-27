const test = require('node:test')
const assert = require('node:assert')
const { actionToOps, vkOf } = require('./control')

const toScreen = ([x, y]) => ({ x: x * 2, y: y * 2 })

test('key combos press in order and release in reverse', () => {
	assert.deepStrictEqual(actionToOps({ action: { name: 'key', text: 'ctrl+shift+t' }, toScreen }), [
		{ t: 'vk', k: 0x11, down: true },
		{ t: 'vk', k: 0x10, down: true },
		{ t: 'vk', k: 0x54, down: true },
		{ t: 'vk', k: 0x54, down: false },
		{ t: 'vk', k: 0x10, down: false },
		{ t: 'vk', k: 0x11, down: false },
	])
})

test('key names', () => {
	assert.strictEqual(vkOf('Return'), 0x0d)
	assert.strictEqual(vkOf('f12'), 0x7b)
	assert.strictEqual(vkOf('cmd'), 0x11)
	assert.throws(() => vkOf('hyper'))
})

test('clicks map screenshot pixels to the screen and hold modifiers', () => {
	const ops = actionToOps({ action: { name: 'double_click', coordinate: [10, 20], text: 'shift' }, toScreen })
	assert.deepStrictEqual(ops[0], { t: 'move', x: 20, y: 40 })
	assert.strictEqual(ops.filter((o) => o.t === 'btn').length, 4)
	assert.deepStrictEqual(ops.at(-1), { t: 'vk', k: 0x10, down: false })
})

test('typing sends unicode code units and Return for newlines', () => {
	const ops = actionToOps({ action: { name: 'type', text: 'hé\n😀' }, toScreen })
	assert.deepStrictEqual(ops.slice(0, 2), [{ t: 'char', c: 104 }, { t: 'char', c: 233 }])
	assert.deepStrictEqual(ops[2], { t: 'vk', k: 0x0d, down: true })
	assert.strictEqual(ops.filter((o) => o.t === 'char').length, 4) // emoji is a surrogate pair
})

test('scroll direction and amount', () => {
	const ops = actionToOps({ action: { name: 'scroll', coordinate: [1, 1], scrollDirection: 'down', scrollAmount: 3 }, toScreen })
	assert.deepStrictEqual(ops[1], { t: 'wheel', d: -360, h: false })
})

test('non-input actions are not ops', () => {
	assert.strictEqual(actionToOps({ action: { name: 'screenshot' }, toScreen }), null)
	assert.throws(() => actionToOps({ action: { name: 'left_click' }, toScreen }))
})
