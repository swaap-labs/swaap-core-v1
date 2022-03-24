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

	while (startIndexIn >= 0) {
		if (endTimestamp - timestampsIn[startIndexIn] > priceStatisticsLookbackInSec) {
			startIndexIn = startIndexIn - 1
		} else {
			break
		}
	}
	if (startIndexIn < ((priceStatisticsLookbackInRound < timestampsIn.length ? priceStatisticsLookbackInRound : timestampsIn.length) - 1)) {
		startIndexIn += 1
	}
	const noMoreDataPointIn = timestampsIn[startIndexIn] < endTimestamp - priceStatisticsLookbackInSec
	while (startIndexOut >= 0) {
		if (endTimestamp - timestampsOut[startIndexOut] > priceStatisticsLookbackInSec) {
			startIndexOut = startIndexOut - 1
		} else {
			break
		}
	}
	if (startIndexOut < ((priceStatisticsLookbackInRound < timestampsOut.length ? priceStatisticsLookbackInRound : timestampsOut.length) - 1)) {
		startIndexOut += 1
	}
	const noMoreDataPointOut = timestampsOut[startIndexOut] < endTimestamp - priceStatisticsLookbackInSec

	if (noMoreDataPointIn && noMoreDataPointOut) {
		const ts = endTimestamp - priceStatisticsLookbackInSec
		timestampsIn[startIndexIn] = ts
		timestampsOut[startIndexOut] = ts
	} else {
		const [_startIndexIn, _startIndexOut] = consolidateStartIndices(
			timestampsIn, startIndexIn,
			timestampsOut, startIndexOut,
			noMoreDataPointIn, noMoreDataPointOut,
			priceStatisticsLookbackInSec, endTimestamp
		)
		startIndexIn = _startIndexIn
		startIndexOut = _startIndexOut
	}

	return [startIndexIn, startIndexOut];
}

function consolidateStartIndices(
		timestampsIn, startIndexIn, timestampsOut, startIndexOut,
		noMoreDataPointIn, noMoreDataPointOut, priceStatisticsLookbackInSec,
		endTimestamp
	) {

	// trim prices/timestamps by adjusting startIndexes
	if (timestampsIn[startIndexIn] > timestampsOut[startIndexOut]) {
		const startTimestamp = timestampsIn[startIndexIn];
		while (startIndexOut  > 0 && timestampsOut[startIndexOut - 1] <= startTimestamp) {
			startIndexOut -= 1;
		}
	} else if (timestampsIn[startIndexIn] < timestampsOut[startIndexOut]) {
		const startTimestamp = timestampsOut[startIndexOut];
		while (startIndexIn > 0 && timestampsIn[startIndexIn - 1] <= startTimestamp) {
			startIndexIn -= 1;
		}
	}

	return [startIndexIn, startIndexOut];
}

function getParametersEstimation(
		pricesIn, timestampsIn, startIndexIn,
		pricesOut, timestampsOut, startIndexOut,
		priceStatisticsLookbackInRound, priceStatisticsLookbackInSec,
		endTimestamp
	) {

	const noMoreDataPointIn = endTimestamp - timestampsIn[startIndexIn] > priceStatisticsLookbackInSec
	const noMoreDataPointOut = endTimestamp - timestampsOut[startIndexOut] > priceStatisticsLookbackInSec

	if (startIndexIn < 0 || startIndexOut < 0) {
		return [0, 0];
	}

	if (timestampsIn.length == 0 || timestampsOut.length == 0) {
		return [0, 0];
	}

	if (startIndexIn == 0 && startIndexOut == 0) {
		return [0, 0];
	}

	const [values, timestamps] = getSeries(
		pricesIn, timestampsIn, startIndexIn,
		pricesOut, timestampsOut, startIndexOut
	)

	return getStatistics(
		values,
		timestamps
	);

}

function getSeries(
	pricesIn, timestampsIn, startIndexIn,
	pricesOut, timestampsOut, startIndexOut,
) {

	let values = [pricesOut[startIndexOut] / pricesIn[startIndexIn]];
	let timestamps = [Math.max(timestampsOut[startIndexOut], timestampsIn[startIndexIn])];

	let skip;
	while (startIndexIn > 0 || startIndexOut > 0) {
		[skip, startIndexIn, startIndexOut] = getNextSample(
			startIndexIn, startIndexOut, timestampsIn, timestampsOut
		);
		if (!skip) {
			values.push(pricesOut[startIndexOut] / pricesIn[startIndexIn]);
			timestamps.push(Math.max(timestampsOut[startIndexOut], timestampsIn[startIndexIn]));
		}
	}
	return [values, timestamps];

}

function getStatistics(values, timestamps) {

	let n = values.length;
	if (n < 2) {
		return [0, 0];
	}
	n -= 1;

	const t = timestamps[n] - timestamps[0]
	// mean
	let mean = Math.log(values[n] / values[0]) / t;

	// variance
	let variance = - Math.pow(mean, 2) * t;
	for (let i=1; i <= n; i++) {
		variance += Math.pow(Math.log(values[i] / values[i - 1]), 2) / (timestamps[i] - timestamps[i - 1]);
	}
	variance /= n

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
    getSeries,
    getStatistics,
    getNextSample,
    getStartIndices
};
