const Decimal = require('decimal.js');

const { calcOutGivenIn } = require('../lib/calc_comparisons');


function getLogSpreadFactor(
		mean, variance, z, horizon
	) {
	return (mean - variance / 2) * horizon + z * Math.sqrt(variance * 2 * horizon)
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

function getInAmountAtPrice(
	tokenBalanceIn,
	tokenWeightIn,
	tokenBalanceOut,
	tokenWeightOut,
	relativePrice
) {
	const weightSum = tokenWeightIn + tokenWeightOut;
	const wOutOverSum = tokenWeightOut / weightSum;
	return (relativePrice * tokenWeightIn / tokenWeightOut)**wOutOverSum * tokenBalanceIn**(tokenWeightIn / weightSum) *  tokenBalanceOut**wOutOverSum
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
	const quantityInAtEquilibrium = getInAmountAtPrice(
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

module.exports = {
    getLogSpreadFactor,
    getMMMWeight,
    getInAmountAtPrice,
    calcOutGivenInMMM,
    computeMMMSpread,
};