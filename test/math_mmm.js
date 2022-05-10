const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff, calcSingleOutGivenPoolIn, calcPoolOutGivenSingleIn } = require('../lib/calc_comparisons');
const {
		getLogSpreadFactor, getMMMWeight,
		getTokenBalanceAtEquilibrium, calcOutGivenInMMM,
		calcAdaptiveFeeGivenInAndOut, getOutTargetGivenIn,
		calcPoolOutGivenSingleInAdaptiveFees,
		calcSingleOutGivenPoolInAdaptiveFees
	} = require('../lib/mmm');

const { getInAmountAtPrice } = require('../lib/mmm');

const TMathMMM = artifacts.require('TMathMMM');
const TConstantOracle = artifacts.require('TConstantOracle');
const TOracle = artifacts.require('TOracle');

const errorDelta = 10 ** -8;

const verbose = process.env.VERBOSE;

const priceStatisticsLookbackInRound = 4;
const priceStatisticsLookbackInSec = 36000;

const nullAddress = "0x0000000000000000000000000000000000000000"


contract('MMM Math', async (accounts) => {

	const now = 42;

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const MAX = web3.utils.toTwosComplement(-1);

    let math;

    let wethOracle; let wethOraclePrice = 300000000000;
    let mkrOracle; let mkrOraclePrice = 10000000000;
    let daiOracle; let daiOraclePrice = 100000000;

    const roundId = 100;

    before(async () => {

		math = await TMathMMM.deployed();

		wethOracle = await TConstantOracle.new(wethOraclePrice, now);
		mkrOracle = await TConstantOracle.new(mkrOraclePrice, now);
		daiOracle = await TConstantOracle.new(daiOraclePrice, now);

    });

	async function assertGBM(mean, variance, z, horizon, weight) {

		// Library logSpreadFactor output
		const logSpreadFactor = await math.getLogSpreadFactor.call(
			toWei(mean.toString()),
			toWei(variance.toString()),
			toWei(z.toString()),
			toWei(horizon.toString())
		);

		// Expected logSpreadFactor output
		const expectedLogSpreadFactor = getLogSpreadFactor(
			mean, variance, z, horizon
		);

		// Checking logSpreadFactor
		const actualLogSpreadFactor = Decimal(fromWei(logSpreadFactor));
		const relDifLogSpreadFactor = calcRelativeDiff(expectedLogSpreadFactor, actualLogSpreadFactor);
		if (verbose) {
			console.log('LogSpreadFactor');
			console.log(`expectedLogSpreadFactor: ${expectedLogSpreadFactor}`);
			console.log(`actual: ${actualLogSpreadFactor}`);
			console.log(`relDif: ${relDifLogSpreadFactor}`);
		}
		assert.isAtMost(relDifLogSpreadFactor.toNumber(), errorDelta);

		// Library MMMWeight output
		const result = await math.getMMMWeight.call(
			toWei(weight.toString()),
			toWei(mean.toString()),
			toWei(variance.toString()),
			toWei(z.toString()),
			toWei(horizon.toString())
		);
		const mmmWeight = result[0]
		const mmmSpread = result[1]

		// Expected MMMWeight output
		const [expectedMMMWeight, expectedMMMSpread] = getMMMWeight(
			weight, mean, variance, z, horizon
		);

		// Checking MMMWeight
		const actualMMMWeight = Decimal(fromWei(mmmWeight));
		const relDifMMMWeight = calcRelativeDiff(expectedMMMWeight, actualMMMWeight);
		if (verbose) {
			console.log('MMMWeight');
			console.log(`expectedMMMWeight: ${expectedMMMWeight}`);
			console.log(`actual: ${actualMMMWeight}`);
			console.log(`relDif: ${relDifMMMWeight}`);
		}
		assert.isAtMost(relDifMMMWeight.toNumber(), errorDelta);

		// Checking MMMSpread
		const actualMMMSpread = Decimal(fromWei(mmmSpread));
		const relDifMMMSpread = calcRelativeDiff(expectedMMMSpread, actualMMMSpread);
		if (verbose) {
			console.log('MMMSpread');
			console.log(`expectedMMMSpread: ${expectedMMMSpread}`);
			console.log(`actual: ${actualMMMSpread}`);
			console.log(`relDif: ${relDifMMMSpread}`);
		}
		assert.isAtMost(relDifMMMSpread.toNumber(), errorDelta);

	}

	async function assertTokenBalanceAtEquilibrium(
		tokenBalanceIn,
		tokenWeightIn,
		tokenBalanceOut,
		tokenWeightOut,
		relativePrice
	) {

		// Library InAmountAtPrice output
		const inAmountAtPrice = await math.getTokenBalanceAtEquilibrium.call(
			toWei(tokenBalanceIn.toString()),
			toWei(tokenWeightIn.toString()),
			toWei(tokenBalanceOut.toString()),
			toWei(tokenWeightOut.toString()),
			toWei(relativePrice.toString())
		);

		// Expected InAmountAtPrice output
		const expectedInAmountAtPrice = getTokenBalanceAtEquilibrium(
			tokenBalanceIn,
			tokenWeightIn,
			tokenBalanceOut,
			tokenWeightOut,
			relativePrice
		);

		// Checking InAmountAtPrice
		const actualInAmountAtPrice = Decimal(fromWei(inAmountAtPrice));
		const relDifInAmountAtPrice = calcRelativeDiff(expectedInAmountAtPrice, actualInAmountAtPrice);
		if (verbose) {
			console.log('InAmountAtPrice');
			console.log(`expectedInAmountAtPrice: ${expectedInAmountAtPrice}`);
			console.log(`actual: ${actualInAmountAtPrice}`);
			console.log(`relDif: ${relDifInAmountAtPrice}`);
		}
		assert.isAtMost(relDifInAmountAtPrice.toNumber(), errorDelta);
	}

	async function assertCalcOutGivenInMMM(
		tokenBalanceIn,
		tokenWeightIn,
		tokenBalanceOut,
		tokenWeightOut,
		tokenAmountIn,
		swapFee,
		mean,
		variance,
		z,
		horizon,
		relativePrice
	) {

		// Library AmountOutMMM output
		const expectedInAmountAtPrice = getTokenBalanceAtEquilibrium(
			tokenBalanceIn,
			tokenWeightIn,
			tokenBalanceOut,
			tokenWeightOut,
			relativePrice
		);

		if (verbose) {
			const gas = await math.calcOutGivenInMMM.estimateGas(
				toWei(tokenBalanceIn.toString()),
				toWei(tokenWeightIn.toString()),
				toWei(tokenBalanceOut.toString()),
				toWei(tokenWeightOut.toString()),
				toWei(tokenAmountIn.toString()),
				toWei(swapFee.toString()),
				toWei(mean.toString()),
				toWei(variance.toString()),
				toWei(z.toString()),
				toWei(horizon.toString()),
				toWei(expectedInAmountAtPrice.toString().slice(0, 18))
			);
			console.log("gas:", gas)
		}

		const result = await math.calcOutGivenInMMM.call(
			toWei(tokenBalanceIn.toString()),
			toWei(tokenWeightIn.toString()),
			toWei(tokenBalanceOut.toString()),
			toWei(tokenWeightOut.toString()),
			toWei(tokenAmountIn.toString()),
			toWei(swapFee.toString()),
			toWei(mean.toString()),
			toWei(variance.toString()),
			toWei(z.toString()),
			toWei(horizon.toString()),
			toWei(expectedInAmountAtPrice.toString().slice(0, 18))
		);
		const amountOutMMM = result[0]
		const mmmSpread = result[1]

		// Expected AmountOutMMM output
		const [expectedAmountOutMMM, expectedMMMSpread] = calcOutGivenInMMM(
			tokenBalanceIn,
			tokenWeightIn,
			tokenBalanceOut,
			tokenWeightOut,
			tokenAmountIn,
			swapFee,
			mean,
			variance,
			z,
			horizon,
			relativePrice
		);

		// Checking MMMSpread
		const actualMMMSpread = Decimal(fromWei(mmmSpread));
		const relDifMMMSpread = calcRelativeDiff(expectedMMMSpread, actualMMMSpread);
		if (verbose) {
			console.log('MMMSpread');
			console.log(`expectedMMMSpread: ${expectedMMMSpread}`);
			console.log(`actual: ${actualMMMSpread}`);
			console.log(`relDif: ${relDifMMMSpread}`);
		}
		assert.isAtMost(relDifMMMSpread.toNumber(), errorDelta);

		// Checking AmountOutMMM
		const actualAmountOutMMM = Decimal(fromWei(amountOutMMM));
		const relDifAmountOutMMM = calcRelativeDiff(expectedAmountOutMMM, actualAmountOutMMM);
		if (verbose) {
			console.log('AmountOutMMM');
			console.log(`expectedAmountOutMMM: ${expectedAmountOutMMM}`);
			console.log(`actual: ${actualAmountOutMMM}`);
			console.log(`relDif: ${relDifAmountOutMMM}`);
		}
		assert.isAtMost(relDifAmountOutMMM.toNumber(), errorDelta);
	}

	async function assertGetOutTargetGivenIn() {

		const balanceIn = 9.995003746877732
		const weightIn = 0.5002498750624688
		const amountIn = 0.004996253122268257

		const balanceOut = 10.004998750624614
		const weightOut = 0.49975012493753124

		const relativePrice = balanceIn / balanceOut * weightOut / weightOut

		// Expected targetOut
		const expectedTargetOut = getOutTargetGivenIn(
			balanceIn, balanceOut, relativePrice, amountIn
		);

		// Actual targetOut
		const targetOut = await math.getOutTargetGivenIn(
			toWei(balanceOut.toString()),
			toWei(relativePrice.toString()),
			toWei(amountIn.toString())
		);

		// Checking targetOut
		const actualTargetOut = Decimal(fromWei(targetOut));
		const relDif = calcRelativeDiff(expectedTargetOut, actualTargetOut);
		if (verbose) {
			console.log('TargetOut');
			console.log(`expected: ${expectedTargetOut}`);
			console.log(`actual: ${actualTargetOut}`);
			console.log(`relDif: ${relDif}`);
		}
		assert.isAtMost(relDif.toNumber(), errorDelta);
	}

	async function assertCalcAdaptiveFeeGivenInAndOut() {

		const balanceIn = 9.995003746877732
		const weightIn = 0.5002498750624688
		const amountIn = 0.004996253122268257

		const balanceOut = 10.004998750624614
		const weightOut = 0.49975012493753124
		const amountOut = 0.005001249375387928

		// Expected adaptiveFees
		const expectedAdaptiveFees = calcAdaptiveFeeGivenInAndOut(
			balanceIn, weightIn, balanceOut, weightOut, amountIn, balanceOut - amountOut
		);

		// Actual adaptiveFees
		const adaptiveFees = await math.calcAdaptiveFeeGivenInAndOut(
			toWei(balanceIn.toString()),
			toWei(amountIn.toString()),
			toWei(weightIn.toString()),
			toWei(balanceOut.toString()),
			toWei(amountOut.toString()),
			toWei(weightOut.toString())
		);

		// Checking adaptiveFees
		const actualAdaptiveFees = Decimal(fromWei(adaptiveFees));
		const relDif = calcRelativeDiff(expectedAdaptiveFees, actualAdaptiveFees);
		if (verbose) {
			console.log('AdaptiveFees');
			console.log(`expected: ${expectedAdaptiveFees}`);
			console.log(`actual: ${actualAdaptiveFees}`);
			console.log(`relDif: ${relDif}`);
		}
		assert.isAtMost(relDif.toNumber(), errorDelta);
	}

	async function assertCalcPoolOutGivenSingleInAdaptiveFees() {

		const poolValueInTokenIn = 19.086622466755248
		const balanceIn = 9.950371902099894
		const weightIn = 0.5238095238095238
		const amountIn = 0.019004798899032026

		// Expected adaptiveFees
		const expectedAdaptiveFees = calcPoolOutGivenSingleInAdaptiveFees(
			poolValueInTokenIn, balanceIn, weightIn, amountIn
		);

		// Actual adaptiveFees
		const adaptiveFees = await math.calcPoolOutGivenSingleInAdaptiveFees(
			toWei(poolValueInTokenIn.toString()),
			toWei(balanceIn.toString()),
			toWei(weightIn.toString()),
			toWei(amountIn.toString())
		);

		// Checking adaptiveFees
		const actualAdaptiveFees = Decimal(fromWei(adaptiveFees));
		const relDif = calcRelativeDiff(expectedAdaptiveFees, actualAdaptiveFees);
		if (verbose) {
			console.log('AdaptiveFees');
			console.log(`expected: ${expectedAdaptiveFees}`);
			console.log(`actual: ${actualAdaptiveFees}`);
			console.log(`relDif: ${relDif}`);
		}
		assert.isAtMost(relDif.toNumber(), errorDelta);
	}

	async function assertCalcSingleOutGivenPoolInAdaptiveFees() {

		const poolValueInPivotToken = 20.11985099348402
		const balanceOut = 10.059925496742009
		const weightOut = 0.4975124378109453
		const normalizedPoolAmountOut = 0.000999000999000999

		// Expected adaptiveFees
		const expectedAdaptiveFees = calcSingleOutGivenPoolInAdaptiveFees(
			poolValueInPivotToken, balanceOut, weightOut, normalizedPoolAmountOut
		);

		// Actual adaptiveFees
		const adaptiveFees = await math.calcSingleOutGivenPoolInAdaptiveFees(
			toWei(poolValueInPivotToken.toString()),
			toWei(balanceOut.toString()),
			toWei(weightOut.toString()),
			toWei(normalizedPoolAmountOut.toString())
		);

		// Checking adaptiveFees
		const actualAdaptiveFees = Decimal(fromWei(adaptiveFees));
		const relDif = calcRelativeDiff(expectedAdaptiveFees, actualAdaptiveFees);
		if (verbose) {
			console.log('AdaptiveFees');
			console.log(`expected: ${expectedAdaptiveFees}`);
			console.log(`actual: ${actualAdaptiveFees}`);
			console.log(`relDif: ${relDif}`);
		}
		assert.isAtMost(relDif.toNumber(), errorDelta);
	}

	async function assertGetBasesTotalValue() {

        const allAddresses = [
        	wethOracle.address, mkrOracle.address, daiOracle.address
        ]
        const allBalances = [100, 2000, 100000]
        const allPrices = [wethOraclePrice, mkrOraclePrice, daiOraclePrice]

		for (let quoteIdx = 0; quoteIdx < allAddresses.length; quoteIdx++) {
			const baseAddress = allAddresses[quoteIdx]
			const basesAddresses = allAddresses.filter((v, idx) => idx != quoteIdx)
			const basesBalance = allBalances.filter((v, idx) => idx != quoteIdx)
			const basesPrices = allPrices.filter((v, idx) => idx != quoteIdx)
			// Expected value
			const expectedValue = basesBalance.reduce((acc, b, idx) => {
				return acc + b * basesPrices[idx] / allPrices[quoteIdx]
			}, 0)

			// Actual value
			const value = await math.getBasesTotalValue(
				baseAddress,
				basesAddresses,
				basesBalance.map(v => toWei(v.toString())),
			);

			// Checking adaptiveFees
			const actualValue = Decimal(fromWei(value));
			const relDif = calcRelativeDiff(expectedValue, actualValue);
			if (verbose) {
				console.log('Value in pivot terms');
				console.log(`expected: ${expectedValue}`);
				console.log(`actual: ${actualValue}`);
				console.log(`relDif: ${relDif}`);
			}
			assert.isAtMost(relDif.toNumber(), errorDelta);
		}

	}

	async function assertGetPreviousPrice() {

		const priceIn = 100
		const tsIn = 1
		const decimalsIn = 8

		const priceOut = 100
		const tsOut = 1
		const decimalsOut = 10

		// Expected adaptiveFees
		const expectedAdaptiveFees = calcAdaptiveFeeGivenInAndOut(
			balanceIn, weightIn, balanceOut, weightOut, amountIn, balanceOut - amountOut
		);

		// Actual adaptiveFees
		const adaptiveFees = await math.calcAdaptiveFeeGivenInAndOut(
			toWei(balanceIn.toString()),
			toWei(amountIn.toString()),
			toWei(weightIn.toString()),
			toWei(balanceOut.toString()),
			toWei(amountOut.toString()),
			toWei(weightOut.toString())
		);

		// Checking adaptiveFees
		const actualAdaptiveFees = Decimal(fromWei(adaptiveFees));
		const relDif = calcRelativeDiff(expectedAdaptiveFees, actualAdaptiveFees);
		if (verbose) {
			console.log('AdaptiveFees');
			console.log(`expected: ${expectedAdaptiveFees}`);
			console.log(`actual: ${actualAdaptiveFees}`);
			console.log(`relDif: ${relDif}`);
		}
		assert.isAtMost(relDif.toNumber(), errorDelta);
	}

	async function assertCalcSingleOutGivenPoolInMMM() {

		// the spread is not considered here

		const joinexitswapParameters = {
			amount: toWei("1"),
			fee: toWei("0.001"),
			fallbackSpread: toWei("0.003"),
			poolSupply: toWei("100")
		}

		const pivotPrices = [3*10**8]
		const pivotTimestamps = [1]
		const pivotDecimals = [8]
		const pivotOracle = await TOracle.new(pivotPrices, pivotTimestamps, pivotDecimals, roundId);
		const pivotOracleAddress = pivotOracle.address;
		const pivotBalance = toWei("140");
		const pivotWeight = toWei("5");

		const otherPrices = [[40*10**8], [1*10**6]]
		const otherTimestamps = [[1], [0]]
		const otherDecimals = [[8], [6]]
		const WETHOracle = await TOracle.new(otherPrices[0], otherTimestamps[0], otherDecimals[0], roundId);
		const DAIOracle = await TOracle.new(otherPrices[1], otherTimestamps[1], otherDecimals[1], roundId);
		const otherOracleAddresses = [WETHOracle.address, DAIOracle.address]
		const otherBalances = [toWei("10"), toWei("400")]
		const otherWeights = [toWei("5"), toWei("5")]

		const totalAdjustedWeight = parseFloat(fromWei(pivotWeight)) + parseFloat(otherWeights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0))

		let fee = parseFloat(fromWei(joinexitswapParameters["fee"]));

		let blockHasPriceUpdate = pivotTimestamps[0] == 0;
		let i = 0;
		while ((!blockHasPriceUpdate) && (i < otherPrices.length)) {
			if (otherTimestamps[i][0] == 0) {
				blockHasPriceUpdate = true;
			}
			++i;
		}
		if (blockHasPriceUpdate) {
			const poolValueInPivotToken = parseFloat(fromWei(pivotBalance)) + otherBalances.reduce((acc, b, idx) => {
				return acc + parseFloat(fromWei(b)) * (otherPrices[idx][0] / (10**otherDecimals[idx][0])) / (pivotPrices[0] / (10**pivotDecimals[0]))
			}, 0)
			fee += calcSingleOutGivenPoolInAdaptiveFees(
				poolValueInPivotToken,
				parseFloat(fromWei(pivotBalance)),
				parseFloat(fromWei(pivotWeight)) / totalAdjustedWeight,
				parseFloat(fromWei(joinexitswapParameters["amount"])) / parseFloat(fromWei(joinexitswapParameters["poolSupply"]))
			);
		}

		const expected = calcSingleOutGivenPoolIn(
            parseFloat(fromWei(pivotBalance)),
            parseFloat(fromWei(pivotWeight)),
            parseFloat(fromWei(joinexitswapParameters["poolSupply"])),
            totalAdjustedWeight,
            parseFloat(fromWei(joinexitswapParameters["amount"])),
            parseFloat(fee)
		)

		const actual = await math.calcSingleOutGivenPoolInMMM(
			pivotOracleAddress,
			pivotBalance,
			pivotWeight,
			otherOracleAddresses,
			otherBalances,
			otherWeights,
			joinexitswapParameters["amount"],
			joinexitswapParameters["fee"],
			joinexitswapParameters["fallbackSpread"],
			joinexitswapParameters["poolSupply"]
		);

		const relDif = calcRelativeDiff(expected, fromWei(actual));
		if (verbose) {
			console.log('LogSpreadFactor');
			console.log(`expected: ${expected}`);
			console.log(`actual: ${fromWei(actual)}`);
			console.log(`relDif: ${relDif}`);
		}
		assert.isAtMost(relDif.toNumber(), errorDelta);

	}

	async function assertCalcPoolOutGivenSingleInMMM() {

		// the spread is not considered here

		const joinexitswapParameters = {
			amount: toWei("1"),
			fee: toWei("0.001"),
			fallbackSpread: toWei("0.003"),
			poolSupply: toWei("100")
		}

		const pivotPrices = [3*10**8]
		const pivotTimestamps = [1]
		const pivotDecimals = [8]
		const pivotOracle = await TOracle.new(pivotPrices, pivotTimestamps, pivotDecimals, roundId);
		const pivotOracleAddress = pivotOracle.address;
		const pivotBalance = toWei("130");
		const pivotWeight = toWei("5");

		const otherPrices = [[40*10**8], [1*10**6]]
		const otherTimestamps = [[1], [0]]
		const otherDecimals = [[8], [6]]
		const WETHOracle = await TOracle.new(otherPrices[0], otherTimestamps[0], otherDecimals[0], roundId);
		const DAIOracle = await TOracle.new(otherPrices[1], otherTimestamps[1], otherDecimals[1], roundId);
		const otherOracleAddresses = [WETHOracle.address, DAIOracle.address]
		const otherBalances = [toWei("10"), toWei("400")]
		const otherWeights = [toWei("5"), toWei("5")]

		const totalAdjustedWeight = parseFloat(fromWei(pivotWeight)) + parseFloat(otherWeights.reduce((acc, v) => acc + parseFloat(fromWei(v)), 0))

		let fee = parseFloat(fromWei(joinexitswapParameters["fee"]));

		let blockHasPriceUpdate = pivotTimestamps[0] == 0;
		let i = 0;
		while ((!blockHasPriceUpdate) && (i < otherPrices.length)) {
			if (otherTimestamps[i][0] == 0) {
				blockHasPriceUpdate = true;
			}
			++i;
		}
		if (blockHasPriceUpdate) {
			const poolValueInPivotToken = parseFloat(fromWei(pivotBalance)) + otherBalances.reduce((acc, b, idx) => {
				return acc + parseFloat(fromWei(b)) * (otherPrices[idx][0] / (10**otherDecimals[idx][0])) / (pivotPrices[0] / (10**pivotDecimals[0]))
			}, 0)
			fee += calcPoolOutGivenSingleInAdaptiveFees(
				poolValueInPivotToken,
				parseFloat(fromWei(pivotBalance)),
				parseFloat(fromWei(pivotWeight)) / totalAdjustedWeight,
				parseFloat(fromWei(joinexitswapParameters["amount"]))
			);
		}

		const expected = calcPoolOutGivenSingleIn(
            parseFloat(fromWei(pivotBalance)),
            parseFloat(fromWei(pivotWeight)),
            parseFloat(fromWei(joinexitswapParameters["poolSupply"])),
            totalAdjustedWeight,
            parseFloat(fromWei(joinexitswapParameters["amount"])),
            parseFloat(fee)
		)

		const actual = await math.calcPoolOutGivenSingleInMMM(
			pivotOracleAddress,
			pivotBalance,
			pivotWeight,
			otherOracleAddresses,
			otherBalances,
			otherWeights,
			joinexitswapParameters["amount"],
			joinexitswapParameters["fee"],
			joinexitswapParameters["fallbackSpread"],
			joinexitswapParameters["poolSupply"]
		);

		const relDif = calcRelativeDiff(expected, fromWei(actual));
		if (verbose) {
			console.log('LogSpreadFactor');
			console.log(`expected: ${expected}`);
			console.log(`actual: ${fromWei(actual)}`);
			console.log(`relDif: ${relDif}`);
		}
		assert.isAtMost(relDif.toNumber(), errorDelta);

	}

    describe('Protocol math', () => {

        [-0.00001, 0.00001].forEach(async _mean => {
        	[0.00001].forEach(async _variance => {
        		[0, 0.5, 1, 2].forEach(async _z => {
        			[0, 7200].forEach(async _horizon => {
						[40].forEach(async _weight => {
							it(
								`GBM Math ${_mean} ${_variance} ${_z} ${_horizon}`,
								async () => {
									await assertGBM(
										_mean,
										_variance,
										_z,
										_horizon,
										_weight
									)
								}
							)
						})
					})
				})
			})
		});

        [80, 100].forEach(async _tokenBalanceIn => {
        	[20, 10].forEach(async _tokenWeightIn => {
        		[100].forEach(async _tokenBalanceOut => {
        			[20].forEach(async _tokenWeightOut => {
						[1, 2.2].forEach(async _relativePrice => {
							[0.025/100].forEach(async _swapFee => {
								it(
									`TokenBalanceAtEquilibrium ${_tokenBalanceIn} ${_tokenWeightIn} ${_tokenBalanceOut} ${_tokenWeightOut} ${_relativePrice} ${_swapFee}`,
									async () => {
										await assertTokenBalanceAtEquilibrium(
											_tokenBalanceIn,
											_tokenWeightIn,
											_tokenBalanceOut,
											_tokenWeightOut,
											_relativePrice
										)
									}
								)
							})
						})
					})
				})
			})
		});

//        [80, 100].forEach(async _tokenBalanceIn => {
//		[20, 10].forEach(async _tokenWeightIn => {
//		[100].forEach(async _tokenBalanceOut => {
//		[20].forEach(async _tokenWeightOut => {
//        [10].forEach(async _tokenAmountIn => {
//        [0.025/100].forEach(async _swapFee => {
//        [-0.000001, 0.000001].forEach(async _mean => {
//		[0.000001].forEach(async _variance => {
//		[1.29].forEach(async _z => {
//		[0, 7200].forEach(async _horizon => {
//		[2.2].forEach(async _relativePrice => {
//			it(
//				`CalcOutGivenInMMM ${_tokenBalanceIn} ${_tokenWeightIn} ${_tokenBalanceOut} ${_tokenWeightOut} ${_tokenAmountIn} ${_swapFee} ${_mean} ${_variance} ${_z} ${_horizon} ${_relativePrice}`,
//				async () => {
//					await assertCalcOutGivenInMMM(
//						_tokenBalanceIn,
//						_tokenWeightIn,
//						_tokenBalanceOut,
//						_tokenWeightOut,
//						_tokenAmountIn,
//						_swapFee,
//						_mean,
//						_variance,
//						_z,
//						_horizon,
//						_relativePrice
//					)
//				}
//			)
//		})
//		})
//		})
//		})
//		})
//		})
//		})
//		})
//		})
//		})
//		})

		it(
			`getOutTargetGivenIn`,
			async () => {
				await assertGetOutTargetGivenIn()
			}
		)

		it(
			`calcAdaptiveFeeGivenInAndOut`,
			async () => {
				await assertCalcAdaptiveFeeGivenInAndOut()
			}
		)

		it(
			`calcSingleInGivenPoolOutAdaptiveFees`,
			async () => {
				await assertCalcPoolOutGivenSingleInAdaptiveFees()
			}
		)

		it(
			`calcSingleOutGivenPoolInAdaptiveFees`,
			async () => {
				await assertCalcSingleOutGivenPoolInAdaptiveFees()
			}
		)

		it(
			`getBasesTotalValue`,
			async () => {
				await assertGetBasesTotalValue()
			}
		)

		it(
			`calcSingleOutGivenPoolInMMM`,
			async () => {
				await assertCalcSingleOutGivenPoolInMMM()
			}
		)

		it(
			`calcPoolOutGivenSingleInMMM`,
			async () => {
				await assertCalcPoolOutGivenSingleInMMM()
			}
		)

    });
});
