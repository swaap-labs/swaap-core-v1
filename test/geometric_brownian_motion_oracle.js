const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff } = require('./lib/calc_comparisons');
const { getOracleDataHistoryAsList } = require('./lib/data');
const {
	getParametersEstimation,
	getSeries,
	getStatistics,
	getStartIndices
} = require('./lib/gbm_oracle');

const TGeometricBrownianMotionOracle = artifacts.require('TGeometricBrownianMotionOracle');
const TWETHOracle = artifacts.require('TWETHOracle');
const TWBTCOracle = artifacts.require('TWBTCOracle');
const TDAIOracle = artifacts.require('TDAIOracle');
const TConstantOracle = artifacts.require('TConstantOracle');

const errorDelta = 10 ** -8;
const varianceErrorDelta = 2 * 10 ** -6;
const negligibleValue = 10 ** -25;

const verbose = process.env.VERBOSE;


contract('GeometricBrownianMotionOracle', async (accounts) => {

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const MAX = web3.utils.toTwosComplement(-1);

	let testData;
	let now;

	const latestRoundIdConstantOracle = 1

	const horizon = 120
	const z = 0.75
	const priceStatisticsLookbackInRound = 6;
	const priceStatisticsLookbackInSec = 3600 * 2;
	const priceStatisticsLookbackStepInRound = 3;

    let gbmOracle;

    before(async () => {
		gbmOracle = await TGeometricBrownianMotionOracle.deployed();
    });

	async function loadTestOracleData() {

		wethOracle = await TWETHOracle.new();
		wbtcOracle = await TWBTCOracle.new();
		daiOracle = await TDAIOracle.new();

		const lastBlock = await web3.eth.getBlock("latest")
		now = lastBlock.timestamp

		wethOracleAddress = wethOracle.address;
		wbtcOracleAddress = wbtcOracle.address;
		daiOracleAddress = daiOracle.address;

		testData = {
			'ETH': {'oracle': wethOracleAddress, 'data': await getOracleDataHistoryAsList(wethOracle, 10, priceStatisticsLookbackStepInRound)},
			'BTC': {'oracle': wbtcOracleAddress, 'data': await getOracleDataHistoryAsList(wbtcOracle, 10, priceStatisticsLookbackStepInRound)},
			'DAI': {'oracle': daiOracleAddress, 'data': await getOracleDataHistoryAsList(daiOracle, 10, priceStatisticsLookbackStepInRound)}
		}
		if (verbose) {
			console.log("now:", now)
		}
	}

	function getHistoricalData(inCurrency, outCurrency) {

		const inRoundId = testData[inCurrency]["data"][0]["round_id"]
		const inPrices = testData[inCurrency]["data"].map(v => parseFloat(v["price"]))
		const inTimestamps = testData[inCurrency]["data"].map(v => parseFloat(v["timestamp"]))

		const outRoundId = testData[outCurrency]["data"][0]["round_id"]
		const outPrices = testData[outCurrency]["data"].map(v => parseFloat(v["price"]))
		const outTimestamps = testData[outCurrency]["data"].map(v => parseFloat(v["timestamp"]))

		return [inRoundId, inPrices, inTimestamps, outRoundId, outPrices, outTimestamps]
	}

	async function assertGetParametersEstimation(
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, inCurrency, outCurrency
		) {

		const [inRoundId, inPrices, inTimestamps, outRoundId, outPrices, outTimestamps] = getHistoricalData(
			inCurrency, outCurrency
		)

		// Library output
		const result = await gbmOracle.getParametersEstimation.call(
			testData[inCurrency]["oracle"], inRoundId, inPrices[0], inTimestamps[0],
			testData[outCurrency]["oracle"], outRoundId, outPrices[0], outTimestamps[0],
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now, priceStatisticsLookbackStepInRound
		);
		const success = result[2];
		assert.equal(success, true);

		const mean = result[0];
		const variance = result[1];

		const [inStartIndex, outStartIndex] = getStartIndices(
			inTimestamps, outTimestamps,
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
		)

		// Expected output
		const [expectedMean, expectedVariance] = getParametersEstimation(
			inPrices, inTimestamps, inStartIndex,
			outPrices, outTimestamps, outStartIndex,
			now, priceStatisticsLookbackStepInRound
		);


		// Checking mean
		let actualMean = Decimal(fromWei(mean));
		let relDifMean = calcRelativeDiff(expectedMean, actualMean);
		if (verbose) {
			console.log('Mean');
			console.log(`expected: ${expectedMean}`);
			console.log(`actual  : ${actualMean}`);
			console.log(`relDif  : ${relDifMean}`);
		}
		assert.isAtMost(relDifMean.toNumber(), errorDelta);

		// Checking variance
		let actualVariance = Decimal(fromWei(variance));
		let relDifVariance = calcRelativeDiff(expectedVariance, actualVariance);
		if (verbose) {
			console.log('Variance');
			console.log(`expected: ${expectedVariance}`);
			console.log(`actual  : ${actualVariance}`);
			console.log(`relDif  : ${relDifVariance}`);
		}
		if (actualVariance > negligibleValue) {
			assert.isAtMost(relDifVariance.toNumber(), varianceErrorDelta);
		}

		// debug only
		if (verbose) {
			console.log(
				"spread in/out:",
				Math.exp(
					(fromWei(mean) - fromWei(variance) / 2) * horizon + z * Math.sqrt(fromWei(variance) * 2 * horizon)
				) - 1
			)

			const [
				inRoundIdBis,
				inPricesBis,
				inTimestampsBis,
				outRoundIdBis,
				outPricesBis,
				outTimestampsBis
			] = getHistoricalData(inCurrency, outCurrency)

			// Library output
			const resultBis = await gbmOracle.getParametersEstimation.call(
				testData[outCurrency]["oracle"], outRoundIdBis, outPricesBis[0], outTimestampsBis[0],
				testData[inCurrency]["oracle"], inRoundIdBis, inPricesBis[0], inTimestampsBis[0],
				priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now, priceStatisticsLookbackStepInRound
			);
			console.log(
				"spread out/in:",
				Math.exp(
					(fromWei(resultBis[0]) - fromWei(resultBis[1]) / 2) * horizon + z * Math.sqrt(fromWei(resultBis[1]) * 2 * horizon)
				) - 1
			)
		}

	}

	async function assertSuccessCondition(inCurrency, outCurrency) {
		const lastBlock = await web3.eth.getBlock("latest")
		now = lastBlock.timestamp

		wethOracle = await TConstantOracle.new(300000000000);
		wbtcOracle = await TConstantOracle.new(4000000000000);

		const priceStatisticsLookbackInRound = 1;
		const priceStatisticsLookbackInSec = 3600 * 2;

		const [inRoundId, inPrices, inTimestamps, outRoundId, outPrices, outTimestamps] = getHistoricalData(
			inCurrency, outCurrency
		)
		const result = await gbmOracle.getParametersEstimation.call(
			wethOracle.address, latestRoundIdConstantOracle, inPrices[0], inTimestamps[0],
			wbtcOracle.address, latestRoundIdConstantOracle, outPrices[0], outTimestamps[0],
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now, priceStatisticsLookbackStepInRound
		);
		assert.equal(result[2], true);
	}


	async function assertFailCondition(inCurrency, outCurrency) {
		const lastBlock = await web3.eth.getBlock("latest")
		now = lastBlock.timestamp

		wethOracle = await TConstantOracle.new(300000000000);
		wbtcOracle = await TConstantOracle.new(4000000000000);

		const priceStatisticsLookbackInRound = 2;
		const priceStatisticsLookbackInSec = 3600 * 2;

		const [inRoundId, inPrices, inTimestamps, outRoundId, outPrices, outTimestamps] = getHistoricalData(
			inCurrency, outCurrency
		)
		const result = await gbmOracle.getParametersEstimation.call(
			wethOracle.address, latestRoundIdConstantOracle, inPrices[0], inTimestamps[0],
			wbtcOracle.address, latestRoundIdConstantOracle, outPrices[0], outTimestamps[0],
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now, priceStatisticsLookbackStepInRound
		);
		assert.equal(result[2], false);
	}


	describe(`GBM Oracle)`, () => {

		[["Test Oracle", loadTestOracleData]]
		.forEach(loader => {

			it(`Loading ${loader[0]} Data`, async () => {
				await loader[1]()
			});

			[1, 3, 4, 5].forEach(async priceStatisticsLookbackInRound => {
				[1800, 3600, 7200].forEach(async priceStatisticsLookbackInSec => {
					it(
						`ETH-DAI: getParametersEstimation ${priceStatisticsLookbackInRound} ${priceStatisticsLookbackInSec}`,
						async () => {
							await assertGetParametersEstimation(
								priceStatisticsLookbackInRound,
								priceStatisticsLookbackInSec,
								"ETH",
								"DAI",
							);
						}
					)
				})
			});

			[1, 3, 4, 5].forEach(async priceStatisticsLookbackInRound => {
				[1800, 3600, 7200].forEach(async priceStatisticsLookbackInSec => {
					it(
						`BTC-ETH: getParametersEstimation ${priceStatisticsLookbackInRound} ${priceStatisticsLookbackInSec}`,
						async () => {
							await assertGetParametersEstimation(
								priceStatisticsLookbackInRound,
								priceStatisticsLookbackInSec,
								"BTC",
								"ETH",
							);
						}
					)
				})
			});

			[1, 3, 4, 5].forEach(async priceStatisticsLookbackInRound => {
				[1800, 3600, 7200].forEach(async priceStatisticsLookbackInSec => {
					it(
						`DAI-BTC: getParametersEstimation ${priceStatisticsLookbackInRound} ${priceStatisticsLookbackInSec}`,
						async () => {
							await assertGetParametersEstimation(
								priceStatisticsLookbackInRound,
								priceStatisticsLookbackInSec,
								"DAI",
								"BTC",
							);
						}
					)
				})
			});

			it('getSeries', async () => {

				const wethOraclePrices = testData["ETH"]["data"].map(v => parseFloat(v["price"]))
				const wethOracleTimestamps = testData["ETH"]["data"].map(v => parseFloat(v["timestamp"]))
				const daiOraclePrices = testData["DAI"]["data"].map(v => parseFloat(v["price"]))
				const daiOracleTimestamps = testData["DAI"]["data"].map(v => parseFloat(v["timestamp"]))

				const [wethOracleStartIndex, daiOracleStartIndex] = getStartIndices(
					wethOracleTimestamps, daiOracleTimestamps, 6, 7200, now
				)

				// Expected output
				const [expectedValues, expectedTimestamps] = getSeries(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex,
				);

				// Library output
				const result = await gbmOracle.getSeries.call(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex
				)
				values = result[0].map(v => fromWei(v))
				timestamps = result[1].map(v => fromWei(v))

				// Checking returns
				let relDif = expectedValues.length > 0 ? values.reduce((acc, r, idx) => {
					return acc + (r - expectedValues[idx]) / (expectedValues[idx] > 0 ? expectedValues[idx] : 1)
				}, 0) / values.length : 0
				if (verbose) {
					console.log('getSeries');
					console.log(`expected: ${expectedValues}`);
					console.log(`actual  : ${values}`);
					console.log(`relDif  : ${relDif}`);
				}
				assert.isAtMost(relDif, errorDelta);

				// Checking timestamps
				relDif = expectedTimestamps.length > 0 ? timestamps.reduce((acc, td, idx) => {
					return acc + (td - expectedTimestamps[idx]) / (expectedTimestamps[idx] > 0 ? expectedTimestamps[idx] : 1)
				}, 0) / values.length : 0
				if (verbose) {
					console.log('getSeries');
					console.log(`expected: ${expectedTimestamps}`);
					console.log(`actual  : ${timestamps}`);
					console.log(`relDif  : ${relDif}`);
				}
				assert.isAtMost(relDif, errorDelta);

			});

			it('getStatistics', async () => {

				const wethOraclePrices = testData["ETH"]["data"].map(v => parseFloat(v["price"]))
				const wethOracleTimestamps = testData["ETH"]["data"].map(v => parseFloat(v["timestamp"]))
				const daiOraclePrices = testData["DAI"]["data"].map(v => parseFloat(v["price"]))
				const daiOracleTimestamps = testData["DAI"]["data"].map(v => parseFloat(v["timestamp"]))

				const [wethOracleStartIndex, daiOracleStartIndex] = getStartIndices(
					wethOracleTimestamps, daiOracleTimestamps, 6, 7200, now
				)

				// Computing parameters
				const [expectedValues, expectedTimestamps] = getSeries(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex,
				);

				// Library output
				if (verbose) {
					const gas = await gbmOracle.getStatistics.estimateGas(
						expectedValues.map(v => toWei(v.toString().slice(0, 20))),
						expectedTimestamps.map(v => toWei(v.toString().slice(0, 20))),
					)
					console.log("gas:", gas)
				}
				let result = await gbmOracle.getStatistics.call(
					expectedValues.map(v => toWei(v.toString().slice(0, 20))),
					expectedTimestamps.map(v => toWei(v.toString().slice(0, 20))),
				)
				const mean = result[0];
				const variance = result[1];

				// Expected output
				const [expectedMean, expectedVariance] = getStatistics(
					expectedValues, expectedTimestamps
				);

				// Checking mean
				let actualMean = Decimal(fromWei(mean));
				let relDifMean = calcRelativeDiff(expectedMean, actualMean);
				if (verbose) {
					console.log('Mean');
					console.log(`expected: ${expectedMean}`);
					console.log(`actual  : ${actualMean}`);
					console.log(`relDif  : ${relDifMean}`);
				}
				assert.isAtMost(relDifMean.toNumber(), errorDelta);

				// Checking variance
				let actualVariance = Decimal(fromWei(variance));
				let relDifVariance = calcRelativeDiff(expectedVariance, actualVariance);
				if (verbose) {
					console.log('Variance');
					console.log(`expected: ${expectedVariance}`);
					console.log(`actual  : ${actualVariance}`);
					console.log(`relDif  : ${relDifVariance}`);
				}
				if (actualVariance > negligibleValue) {
					assert.isAtMost(relDifVariance.toNumber(), varianceErrorDelta);
				}

			});

			it('gbm estimation succeeds', async () => {
				await assertSuccessCondition("ETH", "BTC")
			});

			it('gbm estimation fails', async () => {
				await assertFailCondition("ETH", "BTC")
			});
		})
	})

});
