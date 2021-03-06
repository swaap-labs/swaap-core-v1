const Decimal = require('decimal.js');

const { calcOutGivenIn, calcInGivenOut } = require('../lib/calc_comparisons');


function getLogSpreadFactor(
		mean, variance, z, horizon
	) {
	return mean * horizon + z * Math.sqrt(variance * 2 * horizon)
}

function computeMMMSpread(
		mean, variance, z, horizon
	) {
	if (horizon == 0) {
		return 1;
	}
	const logSpreadFactor = getLogSpreadFactor(mean, variance, z, horizon);
	if (logSpreadFactor <= 0) {
		return 1;
	}
	return Math.exp(logSpreadFactor);
}

function getMMMWeight(
		weight, mean, variance, z, horizon
	) {
	const spread = computeMMMSpread(mean, variance, z, horizon);
	return [weight * spread, spread - 1];
}

function getTokenBalanceAtEquilibrium(
	tokenBalance1,
	tokenWeight1,
	tokenBalance2,
	tokenWeight2,
	relativePrice
) {
	const weightSum = tokenWeight1 + tokenWeight2;
	const wOutOverSum = tokenWeight2 / weightSum;
	return (relativePrice * tokenWeight1 / tokenWeight2)**wOutOverSum * tokenBalance1**(tokenWeight1 / weightSum) *  tokenBalance2**wOutOverSum
}

function calcOutGivenInMMM(
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
	const quantityInAtEquilibrium = getTokenBalanceAtEquilibrium(
		tokenBalanceIn,
		tokenWeightIn,
		tokenBalanceOut,
		tokenWeightOut,
		relativePrice
	);
	const [adjustedTokenOutWeight, spread] = getMMMWeight(tokenWeightOut, mean, variance, z, horizon);
	if (tokenBalanceIn >= quantityInAtEquilibrium) { // shortage of tokenOut --> apply coverage policy
		return [
			calcOutGivenIn(
				tokenBalanceIn,
				tokenWeightIn,
				tokenBalanceOut,
				adjustedTokenOutWeight,
				tokenAmountIn,
				swapFee
			).toNumber(),
			spread
		];
	}
	const tokenInSellAmountForEquilibrium = quantityInAtEquilibrium - tokenBalanceIn;
	return [
		_calcOutGivenInMMMSurplus(
			tokenBalanceIn,
			tokenWeightIn,
			tokenBalanceOut,
			tokenWeightOut,
			tokenAmountIn,
			swapFee,
			adjustedTokenOutWeight,
			tokenInSellAmountForEquilibrium
		),
		spread
	];
}

function _calcOutGivenInMMMSurplus(
	tokenBalanceIn,
	tokenWeightIn,
	tokenBalanceOut,
	tokenWeightOut,
	tokenAmountIn,
	swapFee,
	adjustedTokenWeightOut,
	tokenInSellAmountForEquilibrium
) {
	if (tokenAmountIn < tokenInSellAmountForEquilibrium) { // toward equilibrium --> no coverage fees
		return calcOutGivenIn(
			tokenBalanceIn,
			tokenWeightIn,
			tokenBalanceOut,
			tokenWeightOut,
			tokenAmountIn,
			swapFee
		).toNumber();
	}
	// toward equilibrium --> no coverage fees
	const tokenAmountOutPart1 = calcOutGivenIn(
		tokenBalanceIn,
		tokenWeightIn,
		tokenBalanceOut,
		tokenWeightOut,
		tokenInSellAmountForEquilibrium,
		swapFee
	).toNumber();
	// shortage of tokenOut --> apply coverage policy
	const tokenAmountOutPart2 = calcOutGivenIn(
		tokenBalanceIn + tokenInSellAmountForEquilibrium,
		tokenWeightIn,
		tokenBalanceOut - tokenAmountOutPart1,
		adjustedTokenWeightOut,
		tokenAmountIn - tokenInSellAmountForEquilibrium, // tokenAmountIn > tokenInSellAmountForEquilibrium
		swapFee
	).toNumber();
	return tokenAmountOutPart1 + tokenAmountOutPart2;
}

function calcAdaptiveFeeGivenInAndOut(
	tokenBalanceIn,
	tokenWeightIn,
	tokenBalanceOut,
	tokenWeightOut,
	tokenAmountIn,
	targetBalanceOut
) {
	const alpha = (tokenBalanceIn * (tokenBalanceOut / targetBalanceOut) ** (tokenWeightOut / tokenWeightIn) - (tokenBalanceIn + tokenAmountIn)) / -tokenAmountIn
	return Math.max(alpha, 0)
}

function calcPoolOutGivenSingleInAdaptiveFees(
	poolValueInTokenIn,
	tokenBalanceIn,
	tokenWeightIn,
	tokenAmountIn
) {
	const alpha = (1 - (((tokenAmountIn + poolValueInTokenIn) / poolValueInTokenIn) ** (1 / tokenWeightIn) - 1) * tokenBalanceIn / tokenAmountIn) / (1 - tokenWeightIn)
	return Math.max(0, alpha)
}

function calcSingleOutGivenPoolInAdaptiveFees(
	poolValueInTokenOut,
	tokenBalanceOut,
	tokenWeightOut,
	normalizedPoolAmountOut
) {
	const alpha = (1 - (poolValueInTokenOut * normalizedPoolAmountOut) / (tokenBalanceOut * (1 - (1 - normalizedPoolAmountOut) ** (1 / tokenWeightOut)))) / (1 - tokenWeightOut)
	return Math.max(0, alpha)
}

function getOutTargetGivenIn(
	tokenBalanceIn,
	tokenBalanceOut,
	relativePrice,
	tokenAmountIn,
) {
	const currentPriceInOutTerms = 1 / relativePrice
	const poolValueInOutTerms = tokenBalanceOut + tokenBalanceIn * currentPriceInOutTerms
	const targetOut = (poolValueInOutTerms - (tokenBalanceIn + tokenAmountIn) * currentPriceInOutTerms)
	return targetOut
}

module.exports = {
    getLogSpreadFactor,
    getMMMWeight,
    getTokenBalanceAtEquilibrium,
    calcOutGivenInMMM,
    computeMMMSpread,
    calcAdaptiveFeeGivenInAndOut,
    calcPoolOutGivenSingleInAdaptiveFees,
    calcSingleOutGivenPoolInAdaptiveFees,
    getOutTargetGivenIn
};
