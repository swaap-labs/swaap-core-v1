const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff } = require('../lib/calc_comparisons');
const { getParametersEstimation, getPairReturns, getStatistics, getStartIndices, getTimeWindow } = require('../lib/gbm_oracle');

const TGeometricBrownianMotionOracle = artifacts.require('TGeometricBrownianMotionOracle');
const TWETHOracle = artifacts.require('TWETHOracle');
const TWBTCOracle = artifacts.require('TWBTCOracle');
const TDAIOracle = artifacts.require('TDAIOracle');

const errorDelta = 10 ** -7;

const verbose = process.env.VERBOSE;


contract('GeometricBrownianMotionOracle', async (accounts) => {

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const MAX = web3.utils.toTwosComplement(-1);

	let testData;
	let now = Math.floor(Date.now() / 1000)
	console.log("now:", now)

	const horizon = 120
	const z = 0.75

    let gbmOracle;

    before(async () => {
		gbmOracle = await TGeometricBrownianMotionOracle.deployed();
    });

	async function loadTestOracleData() {

		wethOracle = await TWETHOracle.new();
		wbtcOracle = await TWBTCOracle.new();
		daiOracle = await TDAIOracle.new();

		wethOracleAddress = wethOracle.address;
		wbtcOracleAddress = wbtcOracle.address;
		daiOracleAddress = daiOracle.address;

		testData = {
			'ETH': {'oracle': wethOracleAddress, 'data': [{'round_id': '2018', 'price': '312882040500', 'timestamp': '1641889937'}, {'round_id': '2017', 'price': '311613433829', 'timestamp': '1641886305'}, {'round_id': '2016', 'price': '311445000000', 'timestamp': '1641882671'}, {'round_id': '2015', 'price': '310672718218', 'timestamp': '1641879040'}, {'round_id': '2014', 'price': '311461368677', 'timestamp': '1641875409'}, {'round_id': '2013', 'price': '311394849384', 'timestamp': '1641871778'}]},
			'BTC': {'oracle': wbtcOracleAddress, 'data': [{'round_id': '2021', 'price': '4201340255103', 'timestamp': '1641891047'}, {'round_id': '2020', 'price': '4245514000000', 'timestamp': '1641889577'}, {'round_id': '2019', 'price': '4197967571800', 'timestamp': '1641864920'}, {'round_id': '2018', 'price': '4155911000000', 'timestamp': '1641840072'}, {'round_id': '2017', 'price': '4114025628407', 'timestamp': '1641837070'}, {'round_id': '2016', 'price': '4072208879420', 'timestamp': '1641836334'}]},
			'DAI': {'oracle': daiOracleAddress, 'data': [{'round_id': '2009', 'price': '99990575', 'timestamp': '1641892596'}, {'round_id': '2008', 'price': '100000000', 'timestamp': '1641806161'}, {'round_id': '2007', 'price': '100054178', 'timestamp': '1641719735'}, {'round_id': '2006', 'price': '100034433', 'timestamp': '1641633301'}, {'round_id': '2005', 'price': '100044915', 'timestamp': '1641546877'}, {'round_id': '2004', 'price': '100008103', 'timestamp': '1641460433'}]}
		}
		now = 1641892596
	}

	async function loadMainnetData() {
		testData = require('./data.json')
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

	async function assertGetParametersEstimation(priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, inCurrency, outCurrency) {

		const [inRoundId, inPrices, inTimestamps, outRoundId, outPrices, outTimestamps] = getHistoricalData(inCurrency, outCurrency)

		const [inStartIndex, outStartIndex] = getStartIndices(inTimestamps, outTimestamps, priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now)

		// Library output

		const result = await gbmOracle.getParametersEstimation.call(
			testData[inCurrency]["oracle"], inRoundId, inPrices[0], inTimestamps[0],
			testData[outCurrency]["oracle"], outRoundId, outPrices[0], outTimestamps[0],
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
		);
		const mean = result[0];
		const variance = result[1];

		// Expected output
		const [expectedMean, expectedVariance] = getParametersEstimation(
			inPrices, inTimestamps, inStartIndex,
			outPrices, outTimestamps, outStartIndex,
			priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
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
		assert.isAtMost(relDifVariance.toNumber(), errorDelta);

		// debug only
		if (verbose) {
			console.log("spread in/out:", Math.exp((fromWei(mean) - fromWei(variance) / 2) * horizon + z * Math.sqrt(fromWei(variance) * 2 * horizon)) - 1)

			const [inRoundIdBis, inPricesBis, inTimestampsBis, outRoundIdBis, outPricesBis, outTimestampsBis] = getHistoricalData(inCurrency, outCurrency)

			// Library output
			const resultBis = await gbmOracle.getParametersEstimation.call(
				testData[outCurrency]["oracle"], outRoundIdBis, outPricesBis[0], outTimestampsBis[0],
				testData[inCurrency]["oracle"], inRoundIdBis, inPricesBis[0], inTimestampsBis[0],
				priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, now
			);
			console.log("spread out/in:", Math.exp((fromWei(resultBis[0]) - fromWei(resultBis[1]) / 2) * horizon + z * Math.sqrt(fromWei(resultBis[1]) * 2 * horizon)) - 1)
		}

	}

	describe(`GBM Oracle)`, () => {

		[
//			["Mainnet", loadMainnetData],
			["Test Oracle", loadTestOracleData],
		].forEach(loader => {

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
					wethOracleTimestamps, daiOracleTimestamps, 6, 10000, now
				)

				// Library output
				let periodsReturn = await gbmOracle.getPairReturns.call(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex
				)
				periodsReturn = periodsReturn.map(v => fromWei(v))

				// Expected output
				const expectedPeriodsReturn = getPairReturns(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex,
				);

				// Checking returns
				let relDif = periodsReturn.reduce((acc, r, idx) => acc + (r - expectedPeriodsReturn[idx]) / expectedPeriodsReturn[idx], 0) / periodsReturn.length;
				if (verbose) {
					console.log('getPairReturns');
					console.log(`expected: ${expectedPeriodsReturn}`);
					console.log(`actual  : ${periodsReturn}`);
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
				const expectedPeriodsReturn = getPairReturns(
					wethOraclePrices, wethOracleTimestamps, wethOracleStartIndex,
					daiOraclePrices, daiOracleTimestamps, daiOracleStartIndex,
				);
				const actualTimeWindowInSec = getTimeWindow(
					wethOracleTimestamps, wethOracleStartIndex,
					daiOracleTimestamps, daiOracleStartIndex,
					true, true,
					7200, now
				);

				// Library output
				let result = await gbmOracle.getStatistics.call(
					expectedPeriodsReturn.map(v => toWei(v.toString().slice(0, 18))), actualTimeWindowInSec
				)
				const mean = result[0];
				const variance = result[1];

				// Expected output
				const [expectedMean, expectedVariance] = getStatistics(
					expectedPeriodsReturn, actualTimeWindowInSec
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
				assert.isAtMost(relDifVariance.toNumber(), errorDelta);

			});

		})
	})

});
