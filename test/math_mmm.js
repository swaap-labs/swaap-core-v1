const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff } = require('../lib/calc_comparisons');
const { getLogSpreadFactor, getMMMWeight, getInAmountAtPrice, calcOutGivenInMMM } = require('../lib/mmm');

const TMathMMM = artifacts.require('TMathMMM');

const errorDelta = 10 ** -8;

const verbose = process.env.VERBOSE;

const priceStatisticsLookbackInRound = 4;
const priceStatisticsLookbackInSec = 36000;

const nullAddress = "0x0000000000000000000000000000000000000000"


contract('MMM Math', async (accounts) => {

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const MAX = web3.utils.toTwosComplement(-1);

    let math;

    before(async () => {

		math = await TMathMMM.deployed();

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

	async function assertGetInAmountAtPrice(
		tokenBalanceIn,
		tokenWeightIn,
		tokenBalanceOut,
		tokenWeightOut,
		relativePrice
	) {

		// Library InAmountAtPrice output
		const inAmountAtPrice = await math.getInAmountAtPrice.call(
			toWei(tokenBalanceIn.toString()),
			toWei(tokenWeightIn.toString()),
			toWei(tokenBalanceOut.toString()),
			toWei(tokenWeightOut.toString()),
			toWei(relativePrice.toString())
		);

		// Expected InAmountAtPrice output
		const expectedInAmountAtPrice = getInAmountAtPrice(
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
		const expectedInAmountAtPrice = getInAmountAtPrice(
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
									`GetInAmountAtPrice ${_tokenBalanceIn} ${_tokenWeightIn} ${_tokenBalanceOut} ${_tokenWeightOut} ${_relativePrice} ${_swapFee}`,
									async () => {
										await assertGetInAmountAtPrice(
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

        [80, 100].forEach(async _tokenBalanceIn => {
		[20, 10].forEach(async _tokenWeightIn => {
		[100].forEach(async _tokenBalanceOut => {
		[20].forEach(async _tokenWeightOut => {
        [10].forEach(async _tokenAmountIn => {
        [0.025/100].forEach(async _swapFee => {
        [-0.000001, 0.000001].forEach(async _mean => {
		[0.000001].forEach(async _variance => {
		[1.29].forEach(async _z => {
		[0, 7200].forEach(async _horizon => {
		[2.2].forEach(async _relativePrice => {
			it(
				`CalcOutGivenInMMM ${_tokenBalanceIn} ${_tokenWeightIn} ${_tokenBalanceOut} ${_tokenWeightOut} ${_tokenAmountIn} ${_swapFee} ${_mean} ${_variance} ${_z} ${_horizon} ${_relativePrice}`,
				async () => {
					await assertCalcOutGivenInMMM(
						_tokenBalanceIn,
						_tokenWeightIn,
						_tokenBalanceOut,
						_tokenWeightOut,
						_tokenAmountIn,
						_swapFee,
						_mean,
						_variance,
						_z,
						_horizon,
						_relativePrice
					)
				}
			)
		})
		})
		})
		})
		})
		})
		})
		})
		})
		})
		})

    });
});
