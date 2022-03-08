const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff } = require('../lib/calc_comparisons');

const TChainlinkUtils = artifacts.require('TChainlinkUtils');

const errorDelta = 10 ** -8;

const verbose = process.env.VERBOSE;

const priceStatisticsLookbackInRound = 4;
const priceStatisticsLookbackInSec = 36000;

const nullAddress = "0x0000000000000000000000000000000000000000"


contract('Chainlink Utils', async (accounts) => {

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;

    let chainlinkUtils;

    before(async () => {

		chainlinkUtils = await TChainlinkUtils.deployed();

    });

	async function assertGetPreviousPrice(tsIn, tsOut, expected) {

		const newPriceIn = 200
		const priceIn = 100
		const decimalsIn = 2

		const newPriceOut = 500
		const priceOut = 10000
		const decimalsOut = 3

		const actual = await chainlinkUtils.getPreviousPrice(
			toWei(priceIn.toString()),
			toWei(tsIn.toString()),
			decimalsIn,
			toWei(newPriceIn.toString()),
			toWei(priceOut.toString()),
			toWei(tsOut.toString()),
			decimalsOut,
			toWei(newPriceOut.toString()),
		)

		// Checking
		const relDif = calcRelativeDiff(expected, Decimal(fromWei(actual)));
		if (verbose) {
			console.log('Previous Price');
			console.log(`expected: ${expected}`);
			console.log(`actual: ${fromWei(actual)}`);
			console.log(`relDif: ${relDif}`);
		}
		assert.isAtMost(relDif.toNumber(), errorDelta);
	}

    describe('Chainlink Utils', () => {

		[
			[10, 9, 500 / 100 / 10], [9, 10, 10000 / 200 / 10], [10, 10, 10000 / 100 / 10]
		].forEach(async t => {

			const [tsIn, tsOut, expected] = t

			it(
				`getPreviousPrice ${tsIn} ${tsOut}`,
				async () => {
					await assertGetPreviousPrice(tsIn, tsOut, expected)
				}
			)
		})

    });
});
