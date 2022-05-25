const Decimal = require('decimal.js')


async function getAllOracleDataHistory(oracle, maxNumberOfRounds, step) {
	prices = []
	timestamps = []
	roundIds = []
	const result = await oracle.latestRoundData()
	let count = 1
	let roundId = result[0]
	let price = result[1] / 1
	let ts = result[3] / 1
	prices.push(price)
	timestamps.push(ts)
	roundIds.push(roundId)
	while (roundId > 0 && price > 0 && ts > 0 && count < maxNumberOfRounds) {
		console.log("roundId:", roundId, step)
		roundId -= step
		const _result = await oracle.getRoundData(roundId)
		price = _result[1] / 1
		ts = _result[3] / 1
		prices.push(price)
		timestamps.push(ts)
		roundIds.push(roundId)
		count += 1
	}
	return [prices, timestamps, roundIds]
}

async function getOracleDataHistory(oracle, maxNumberOfRounds, step) {
	const [prices, timestamps, roundIds] = await getAllOracleDataHistory(oracle, maxNumberOfRounds, step)
	return [prices, timestamps]
}

async function getOracleDataHistoryAsList(oracle, maxNumberOfRounds, step) {
	const [prices, timestamps, roundIds] = await getAllOracleDataHistory(oracle, maxNumberOfRounds, step)
	const l = roundIds.reduce((acc, curr, i) => {
		return acc.concat(
			{
				"round_id": String(roundIds[i]),
				"price": String(prices[i]),
				"timestamp": String(timestamps[i]),
			}
		)
	}, [])
	return l
}

module.exports = {
    getOracleDataHistory,
    getOracleDataHistoryAsList
}
