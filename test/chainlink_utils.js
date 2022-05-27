const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff } = require('../lib/calc_comparisons');

const TChainlinkUtils = artifacts.require('TChainlinkUtils');
const TOracle = artifacts.require('TOracle');

const errorDelta = 10 ** -8;

const verbose = process.env.VERBOSE;

const priceStatisticsLookbackInRound = 4;
const priceStatisticsLookbackInSec = 36000;

const nullAddress = "0x0000000000000000000000000000000000000000"


contract('Chainlink Utils', async (accounts) => {

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;

    let chainlinkUtils;

    const roundId = 100

    before(async () => {

		chainlinkUtils = await TChainlinkUtils.deployed();

    });

	async function assertGetMaxRelativePriceInLastBlock(
			inPrices, inTimestamps, inDecimals,
			outPrices, outTimestamps, outDecimals,
			expectedIn, expectedOut
		) {

		inOracle = await TOracle.new(inPrices, inTimestamps, inDecimals, roundId);
		outOracle = await TOracle.new(outPrices, outTimestamps, outDecimals, roundId);

		const roundDataIn = await inOracle.latestRoundData();
		const roundDataOut = await outOracle.latestRoundData();

		const actual = await chainlinkUtils.getMaxRelativePriceInLastBlock(
			inOracle.address,
			inDecimals,
			outOracle.address,
			outDecimals
		)

		// Checking
		expected = (expectedOut / 10**outDecimals) / (expectedIn / 10**inDecimals)
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
			[[3, 2, 1], [0, 1, 1], 0, [10, 20, 40], [0, 2, 2], 1, 2, 20],
			[[3, 2, 1], [0, 1, 1], 0, [10, 20, 40], [1, 2, 2], 1, 2, 10],
			[[3, 2, 1], [1, 1, 1], 0, [10, 20, 40], [0, 2, 2], 1, 3, 20],
			[[3, 2, 1], [1, 1, 1], 0, [10, 20, 40], [1, 2, 2], 1, 3, 10],
			[[3, 2, 1], [0, 0, 1], 0, [10, 20, 40], [0, 0, 2], 1, 1, 40],
			[[3, 2, 1], [0, 0, 1], 0, [15, 20, 40], [0, 1, 2], 1, 1, 20],
			[[3, 2, 1], [0, 1, 1], 0, [15, 20, 40], [0, 1, 2], 1, 2, 20],

			[[1, 2, 3], [0, 1, 1], 0, [10, 20, 40], [0, 0, 2], 1, 1, 40],
			[[1, 2, 3], [0, 1, 1], 0, [10, 20, 40], [0, 1, 2], 1, 1, 20],
			[[1, 2, 3], [0, 1, 1], 0, [40, 20, 10], [0, 0, 2], 1, 1, 40],

			[[10, 20, 1], [0, 1, 1], 0, [1, 1, 1], [0, 0, 2], 1, 10, 1],
			[[10, 20, 1], [1, 1, 1], 0, [1, 1, 1], [0, 0, 2], 1, 10, 1],

			[[20, 10, 1], [0, 1, 1], 0, [1, 1, 1], [0, 0, 2], 1, 10, 1],
			[[20, 10, 30], [1, 1, 1], 0, [1, 1, 1], [0, 0, 2], 1, 20, 1],
		].forEach(async t => {

			const [
				inPrices, inTimestamps, inDecimals,
            	outPrices, outTimestamps, outDecimals,
            	expectedIn, expectedOut
            ] = t

			it(
				`getRecentPriceLowerBound expectedIn=${expectedIn} expectedOut=${expectedOut} `,
				async () => {
					await assertGetMaxRelativePriceInLastBlock(
						inPrices, inTimestamps, inDecimals,
						outPrices, outTimestamps, outDecimals,
						expectedIn, expectedOut
					)
				}
			)
		})

    });
});
