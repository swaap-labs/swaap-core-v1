const TMath = artifacts.require('TMath');
const TErr = artifacts.require("TErr");
const Math = artifacts.require("Math");
const TMathMMM = artifacts.require("TMathMMM");
const TChainlinkUtils = artifacts.require("TChainlinkUtils");
const TGeometricBrownianMotionOracle = artifacts.require("TGeometricBrownianMotionOracle");
const GeometricBrownianMotionOracle = artifacts.require("GeometricBrownianMotionOracle");
const Factory = artifacts.require("Factory");

module.exports = async function (deployer, network, accounts) {
	let gasPrice = await web3.eth.getGasPrice();
	gasPrice = await web3.eth.getGasPrice();
	await deployer.deploy(GeometricBrownianMotionOracle, {gasPrice: gasPrice});
	await deployer.link(GeometricBrownianMotionOracle, Math);
	gasPrice = await web3.eth.getGasPrice();
	await deployer.deploy(Math, {gasPrice: gasPrice});
	await deployer.link(Math, Factory);
	gasPrice = await web3.eth.getGasPrice();
	let factory = await deployer.deploy(Factory, {gasPrice: gasPrice});
	console.log(`Factory address: ${factory.address}`);

	if(process.env.SWAAP_LABS !== undefined) {
		gasPrice = await web3.eth.getGasPrice();
		await factory.transferOwnership(process.env.SWAAP_LABS, {gasPrice: gasPrice});
		console.log(`Ownership transfer requested to ${process.env.SWAAP_LABS}`);
	}

	if (network === 'dev' || network === 'coverage' || network === 'test') {
		await deployer.deploy(TErr);
		await deployer.deploy(TMath);
		await deployer.link(GeometricBrownianMotionOracle, TGeometricBrownianMotionOracle);
		await deployer.deploy(TGeometricBrownianMotionOracle);
		await deployer.link(Math, TMathMMM);
		await deployer.deploy(TMathMMM);
		await deployer.deploy(TChainlinkUtils);
	}
};
