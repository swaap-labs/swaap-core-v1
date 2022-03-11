const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff } = require('../lib/calc_comparisons');
const { getOracleDataHistoryAsList } = require('../lib/data');
const {
	getParametersEstimation,
	getPairReturns,
	getStatistics,
	getStartIndices
} = require('../lib/gbm_oracle');

const TGeometricBrownianMotionOracle = artifacts.require('TGeometricBrownianMotionOracle');
const TWETHOracle = artifacts.require('TWETHOracle');
const TWBTCOracle = artifacts.require('TWBTCOracle');
const TDAIOracle = artifacts.require('TDAIOracle');

const errorDelta = 10 ** -6;
const negligibleValue = 10 ** -25;

const verbose = process.env.VERBOSE;
const useMainnetData = process.env.MAINNETDATA;


contract('GeometricBrownianMotionOracle', async (accounts) => {

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const MAX = web3.utils.toTwosComplement(-1);

	let testData;
	let now;

	const horizon = 120
	const z = 0.75

    let gbmOracle;

    before(async () => {
		gbmOracle = await TGeometricBrownianMotionOracle.deployed();
    });

	async function loadTestOracleData() {

		now = 1641893000;

		wethOracle = await TWETHOracle.new(now);
		wbtcOracle = await TWBTCOracle.new(now);
		daiOracle = await TDAIOracle.new(now);

		wethOracleAddress = wethOracle.address;
		wbtcOracleAddress = wbtcOracle.address;
		daiOracleAddress = daiOracle.address;

		testData = {
			'ETH': {'oracle': wethOracleAddress, 'data': await getOracleDataHistoryAsList(wethOracle, 10)},
			'BTC': {'oracle': wbtcOracleAddress, 'data': await getOracleDataHistoryAsList(wbtcOracle, 10)},
			'DAI': {'oracle': daiOracleAddress, 'data': await getOracleDataHistoryAsList(daiOracle, 10)}
		}
		if (verbose) {
			console.log("now:", now)
		}
	}

	async function loadMainnetData() {
		testData = require('./data.json')
		now = Math.max(...[
			parseInt(testData["ETH"]["data"][0]["timestamp"]),
			parseInt(testData["BTC"]["data"][0]["timestamp"]),
			parseInt(testData["DAI"]["data"][0]["timestamp"])
		]);
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

		const [inStartIndex, outStartIndex] = getStartIndices(
			inTimestamps, outTimestamps,
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
		)

		// Expected output
		const [expectedMean, expectedVariance] = getParametersEstimation(
			inPrices, inTimestamps, inStartIndex,
			outPrices, outTimestamps, outStartIndex,
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now,
		);

		// Library output
		const result = await gbmOracle.getParametersEstimation.call(
			testData[inCurrency]["oracle"], inRoundId, inPrices[0], inTimestamps[0],
			testData[outCurrency]["oracle"], outRoundId, outPrices[0], outTimestamps[0],
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
		);
		const mean = result[0];
		const variance = result[1];


		// Checking mean
		let actualMean = Decimal(fromWei(mean));
		let relDifMean = calcRelativeDiff(expectedMean, actualMean);
		if (verbose) {
			console.log('Mean');
			console.log(`expected: ${expectedMean}`);
			console.log(`actual  : ${actualMean}`);
			console.log(`relDif  : ${relDifMean}`);
		}
//		assert.isAtMost(relDifMean.toNumber(), errorDelta);

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
			assert.isAtMost(relDifVariance.toNumber(), errorDelta);
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
				priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
			);
			console.log(
				"spread out/in:",
				Math.exp(
					(fromWei(resultBis[0]) - fromWei(resultBis[1]) / 2) * horizon + z * Math.sqrt(fromWei(resultBis[1]) * 2 * horizon)
				) - 1
			)
		}

	}

	describe(`GBM Oracle)`, () => {

		(
			useMainnetData ?
			[
				["Mainnet", loadMainnetData],
				["Test Oracle", loadTestOracleData],
			] :
			[["Test Oracle", loadTestOracleData]]
		).forEach(loader => {

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

			it('getPairReturns', async () => {

				const wethOraclePrices = testData["ETH"]["data"].map(v => parseFloat(v["price"]))
				const wethOracleTimestamps = testData["ETH"]["data"].map(v => parseFloat(v["timestamp"]))
				const daiOraclePrices = testData["DAI"]["data"].map(v => parseFloat(v["price"]))
				const daiOracleTimestamps = testData["DAI"]["data"].map(v => parseFloat(v["timestamp"]))

				const [wethOracleStartIndex, daiOracleStartIndex] = getStartIndices(
					wethOracleTimestamps, daiOracleTimestamps, 6, 7200, now
				)

				// Expected output
				const [expectedPeriodsReturn, expectedTimeDeltas] = getPairReturns(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex,
				);

				// Library output
				const result = await gbmOracle.getPairReturns.call(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex
				)
				periodsReturn = result[0].map(v => fromWei(v))
				timeDeltas = result[1].map(v => fromWei(v))

				// Checking returns
				let relDif = expectedPeriodsReturn.length > 0 ? periodsReturn.reduce((acc, r, idx) => {
					return acc + (r - expectedPeriodsReturn[idx]) / (expectedPeriodsReturn[idx] > 0 ? expectedPeriodsReturn[idx] : 1)
				}, 0) / periodsReturn.length : 0
				if (verbose) {
					console.log('getPairReturns');
					console.log(`expected: ${expectedPeriodsReturn}`);
					console.log(`actual  : ${periodsReturn}`);
					console.log(`relDif  : ${relDif}`);
				}
				assert.isAtMost(relDif, errorDelta);

				// Checking timeDeltas
				relDif = expectedTimeDeltas.length > 0 ? timeDeltas.reduce((acc, td, idx) => {
					return acc + (td - expectedTimeDeltas[idx]) / (expectedTimeDeltas[idx] > 0 ? expectedTimeDeltas[idx] : 1)
				}, 0) / periodsReturn.length : 0
				if (verbose) {
					console.log('getPairReturns');
					console.log(`expected: ${expectedTimeDeltas}`);
					console.log(`actual  : ${timeDeltas}`);
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
				const [expectedPeriodsReturn, expectedTimeDeltas] = getPairReturns(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex,
				);

				// Library output
				if (verbose) {
					const gas = await gbmOracle.getStatistics.estimateGas(
						expectedPeriodsReturn.map(v => toWei(v.toString().slice(0, 18))),
						expectedTimeDeltas.map(v => toWei(v.toString().slice(0, 18)))
					)
					console.log("gas:", gas)
				}
				let result = await gbmOracle.getStatistics.call(
					expectedPeriodsReturn.map(v => toWei(v.toString().slice(0, 18))),
					expectedTimeDeltas.map(v => toWei(v.toString().slice(0, 18)))
				)
				const mean = result[0];
				const variance = result[1];

				// Expected output
				const [expectedMean, expectedVariance] = getStatistics(
					expectedPeriodsReturn, expectedTimeDeltas
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
					assert.isAtMost(relDifVariance.toNumber(), errorDelta);
				}

			});

		})
	})

});
