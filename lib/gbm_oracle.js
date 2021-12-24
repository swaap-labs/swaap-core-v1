const Decimal = require('decimal.js');

function getStartIndices(timestampsIn, timestampsOut, priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, endTimestamp) {

	let startIndexIn = timestampsIn.length - 1
	let startIndexOut = timestampsOut.length - 1

	if (startIndexIn > priceStatisticsLookbackInRound - 1) {
		startIndexIn = priceStatisticsLookbackInRound - 1
	}
	if (startIndexOut > priceStatisticsLookbackInRound - 1) {
		startIndexOut = priceStatisticsLookbackInRound - 1
	}

	let noMoreDataPointIn = false
	while (startIndexIn >= 0) {
		if (endTimestamp - timestampsIn[startIndexIn] > priceStatisticsLookbackInSec) {
			startIndexIn = startIndexIn - 1
		} else {
			noMoreDataPointIn = true
			break
		}
	}
	if (startIndexIn < ((priceStatisticsLookbackInRound < timestampsIn.length ? priceStatisticsLookbackInRound : timestampsIn.length) - 1)) {
		startIndexIn += 1
	}
	let noMoreDataPointOut = false
	while (startIndexOut >= 0) {
		if (endTimestamp - timestampsOut[startIndexOut] > priceStatisticsLookbackInSec) {
			startIndexOut = startIndexOut - 1
		} else {
			noMoreDataPointOut = true
			break
		}
	}
	if (startIndexOut < ((priceStatisticsLookbackInRound < timestampsOut.length ? priceStatisticsLookbackInRound : timestampsOut.length) - 1)) {
		startIndexOut += 1
	}

	return [startIndexIn, startIndexOut];
}

function getTimeWindow(
		timestampsIn, startIndexIn, timestampsOut, startIndexOut,
		noMoreDataPointIn, noMoreDataPointOut, priceStatisticsLookbackInSec,
		endTimestamp
	) {

	let actualTimeWindowInSec;
	if (noMoreDataPointIn && noMoreDataPointOut) {
		actualTimeWindowInSec = priceStatisticsLookbackInSec
	} else {

		let startTimestamp;
		if (noMoreDataPointIn) {
			startTimestamp = timestampsOut[startIndexOut];
			while (startIndexIn > 0 && timestampsIn[startIndexIn - 1] <= startTimestamp) {
				startIndexIn--;
			}
		} else if (noMoreDataPointOut) {
			startTimestamp = timestampsIn[startIndexIn];
			while (startIndexOut > 0 && timestampsOut[startIndexOut - 1] <= startTimestamp) {
				startIndexOut--;
			}
		} else {
			// trim prices/timestamps by adjusting startIndexes
			if (timestampsIn[startIndexIn] > timestampsOut[startIndexOut]) {
				startTimestamp = timestampsIn[startIndexIn];
				while (startIndexOut  > 0 && timestampsOut[startIndexOut - 1] <= startTimestamp) {
					startIndexOut--;
				}
			} else {
				startTimestamp = timestampsOut[startIndexOut];
				while (startIndexIn > 0 && timestampsIn[startIndexIn - 1] <= startTimestamp) {
					startIndexIn--;
				}
			}
		}

		// considering data points max timestamp difference
		if (endTimestamp <= priceStatisticsLookbackInSec) {
			actualTimeWindowInSec = priceStatisticsLookbackInSec;
		} else {
			if (endTimestamp - priceStatisticsLookbackInSec > startTimestamp) {
				actualTimeWindowInSec = priceStatisticsLookbackInSec;
			} else {
				actualTimeWindowInSec = endTimestamp - startTimestamp;
			}
		}

	}
	return actualTimeWindowInSec;
}

function getParametersEstimation(
		pricesIn, timestampsIn, startIndexIn,
		pricesOut, timestampsOut, startIndexOut,
		priceStatisticsLookbackInRound, priceStatisticsLookbackInSec, endTimestamp
	) {

	const noMoreDataPointIn = endTimestamp - timestampsIn[startIndexIn] > priceStatisticsLookbackInSec
	const noMoreDataPointOut = endTimestamp - timestampsOut[startIndexOut] > priceStatisticsLookbackInSec

	if (noMoreDataPointIn && !noMoreDataPointOut && startIndexIn > 0) {
		startIndexIn -= 1;
	}
	if (noMoreDataPointOut && !noMoreDataPointIn && startIndexOut > 0){
		startIndexOut -= 1;
	}

	if (startIndexIn < 0 || startIndexOut < 0) {
		return [0, 0];
	}

	if (timestampsIn.length == 0 || timestampsOut.length == 0) {
		return [0, 0];
	}

	if (startIndexIn == 0 && startIndexOut == 0) {
		return [0, 0];
	}

	const actualTimeWindowInSec = getTimeWindow(
		timestampsIn, startIndexIn,
		timestampsOut, startIndexOut,
		noMoreDataPointIn, noMoreDataPointOut,
		priceStatisticsLookbackInSec, endTimestamp
	)

	const periodsReturn = getPairReturns(
		pricesIn, timestampsIn, startIndexIn,
		pricesOut, timestampsOut, startIndexOut
	)

	return getStatistics(
		periodsReturn,
		actualTimeWindowInSec
	);

}

function getPairReturns(
	pricesIn, timestampsIn, startIndexIn,
	pricesOut, timestampsOut, startIndexOut,
) {

	let periodsReturn = [];

	let currentPrice = pricesOut[startIndexOut] / pricesIn[startIndexIn];
	let skip = true;
	while (startIndexIn > 0 || startIndexOut > 0) {
		[skip, startIndexIn, startIndexOut] = getNextSample(
			startIndexIn, startIndexOut, timestampsIn, timestampsOut
		);
		if (!skip) {
			const futurePrice = pricesOut[startIndexOut] / pricesIn[startIndexIn];
			periodsReturn.push((futurePrice - currentPrice) / currentPrice);
			currentPrice = futurePrice;
		}
	}
	return periodsReturn;

}

function getStatistics(periodsReturn, actualTimeWindowInSec) {
	let n = periodsReturn.length;
	if (actualTimeWindowInSec == 0) {
		return [0, 0];
	}

	// mean
	let mean = 0;
	for (let i=0; i < n; i++) {
		mean += periodsReturn[i];
	}
	mean = mean / actualTimeWindowInSec;

	// variance
	variance = (actualTimeWindowInSec - n) * mean * mean;
	for (let i=0; i < n; i++) {
		const d = periodsReturn[i] - mean;
		variance += d * d;
	}
	variance = variance / (actualTimeWindowInSec - 1);

	return [mean, variance];
}

function getNextSample(_startIndexIn, _startIndexOut, timestampsIn, timestampsOut) {
	let nextStartIndexIn = _startIndexIn > 0 ? _startIndexIn - 1 : 0;
	let nextStartIndexOut = _startIndexOut > 0 ? _startIndexOut - 1 : 0;
	let skip = true;
	if (timestampsIn[nextStartIndexIn] == timestampsOut[nextStartIndexOut]) {
		if (timestampsIn[nextStartIndexIn] != timestampsIn[_startIndexIn] && timestampsOut[nextStartIndexOut] != timestampsOut[_startIndexOut]) {
			skip = false
		}
		if (_startIndexIn > 0) {
			_startIndexIn -= 1
		}
		if (_startIndexOut > 0) {
			_startIndexOut -= 1
		}
	} else {
		if (_startIndexOut == 0) {
			if (timestampsIn[nextStartIndexIn] != timestampsIn[_startIndexIn]) {
				skip = false
			}
			if (_startIndexIn > 0) {
				_startIndexIn -= 1
			}
		} else if (_startIndexIn == 0) {
			if (timestampsOut[nextStartIndexOut] != timestampsOut[_startIndexOut]) {
				skip = false
			}
			if (_startIndexOut > 0) {
				_startIndexOut -= 1
			}
		} else {
			if (timestampsIn[nextStartIndexIn] < timestampsOut[nextStartIndexOut]) {
				if (timestampsIn[nextStartIndexIn] != timestampsIn[_startIndexIn]) {
					skip = false
				}
				if (_startIndexIn > 0) {
					_startIndexIn -= 1
				}
			} else {
				if (timestampsOut[nextStartIndexOut] != timestampsOut[_startIndexOut]) {
					skip = false
				}
				if (_startIndexOut > 0) {
					_startIndexOut -= 1
				}
			}
		}
	}
	return [skip, _startIndexIn, _startIndexOut];
}

module.exports = {
    getParametersEstimation,
    getPairReturns,
    getStatistics,
    getNextSample,
    getStartIndices,
    getTimeWindow,
};
