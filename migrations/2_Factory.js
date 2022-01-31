const TMath = artifacts.require('TMath');
const Num = artifacts.require("Num");
const Math = artifacts.require("Math");
const TMathMMM = artifacts.require("TMathMMM");
const TGeometricBrownianMotionOracle = artifacts.require("TGeometricBrownianMotionOracle");
const GeometricBrownianMotionOracle = artifacts.require("GeometricBrownianMotionOracle");
const TWETHOracle = artifacts.require("TWETHOracle");
const TDAIOracle = artifacts.require("TDAIOracle");
const TWBTCOracle = artifacts.require("TWBTCOracle");
const Factory = artifacts.require("Factory");

module.exports = async function (deployer, network, accounts) {
	deployer.deploy(Num);
	deployer.link(Num, GeometricBrownianMotionOracle);
	deployer.deploy(GeometricBrownianMotionOracle);
	deployer.link(Num, Math);
	deployer.link(GeometricBrownianMotionOracle, Math);
	deployer.deploy(Math);
	deployer.link(Math, Factory);
	deployer.link(Num, Factory);
	deployer.deploy(Factory);

	if (network === 'dev' || network === 'coverage' || network === 'test') {
		deployer.link(Num, TMath);
		deployer.deploy(TMath);
		deployer.link(Num, TGeometricBrownianMotionOracle);
		deployer.link(GeometricBrownianMotionOracle, TGeometricBrownianMotionOracle);
		deployer.deploy(TGeometricBrownianMotionOracle);
		deployer.link(Math, TMathMMM);
		deployer.deploy(TMathMMM);
//		deployer.deploy(TWETHOracle);
//		deployer.deploy(TDAIOracle);
	}
};
