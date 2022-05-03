// @nhancv
// npx hardhat node
// truffle test ./test/MultiSigEIP712.test.js --network testconst Web3 = require('web3');
const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const TConstantOracle = artifacts.require('TConstantOracle');
const truffleAssert = require('truffle-assertions');
const { sign } = require('../lib/eip712JoinPool');
const { advanceBlock } = require('../lib/time');
const TProxy = artifacts.require('TProxy');

contract('Pool - JIT blocking mechanism', async (accounts) => {
  
  const now = 1641893000;

  const admin = accounts[0];
  const user1 = accounts[1];
  const { toWei } = web3.utils;
  const MAX = web3.utils.toTwosComplement(-1);

  let WETH; let DAI; let WBTC;
  let weth; let dai; let wbtc;
  let factory; // Pool factory
  let pool; // first pool w/ defaults
  let POOL; //   pool address

  let wethOracle;
  let daiOracle;
  let wbtcOracle;

  let WETHOracleAddress;
  let DAIOracleAddress;
  let WBTCOracleAddress;

  before(async () => {
    factory = await Factory.deployed();

    POOL = await factory.newPool.call();
    await factory.newPool();
    pool = await Pool.at(POOL);

    weth = await TToken.new('Wrapped Ether', 'WETH', 18);
    dai = await TToken.new('Dai Stablecoin', 'DAI', 18);
    wbtc = await TToken.new('Wrapped Bitcoin', 'MKR', 18);

    WETH = weth.address;
    DAI = dai.address;
    WBTC = wbtc.address;

    /*
        Tests assume token prices
        WETH - $3000
        DAI  - $1
        WBTC - $45000
    */
    wethOracle = await TConstantOracle.new(300000000000, now);
    daiOracle = await TConstantOracle.new(100000000, now);
    wbtcOracle = await TConstantOracle.new(4500000000000, now);

    WETHOracleAddress = wethOracle.address;
    DAIOracleAddress = daiOracle.address;
    WBTCOracleAddress = wbtcOracle.address;

    // Admin balances
    await weth.mint(admin, toWei('150000'));
    await dai.mint(admin, toWei('450000000'));
    await wbtc.mint(admin, toWei('10000'));

    await weth.approve(POOL, MAX);
    await dai.approve(POOL, MAX);
    await wbtc.approve(POOL, MAX);

    await pool.bindMMM(WETH, toWei('1500'), toWei('5'), WETHOracleAddress);
    await pool.bindMMM(DAI, toWei('4500000'), toWei('5'), DAIOracleAddress);
    await pool.bindMMM(WBTC, toWei('100'), toWei('5'), WBTCOracleAddress); 

    await pool.finalize();
  });

  it('Join pool using tx.origin', async () => {
    let poolAmountOut = toWei('100');
    let maxAmountsIn = [toWei('1500'), toWei('4500000'), toWei('100')];

    // The funds will be taken from the caller
    await pool.joinPoolForTxOrigin(poolAmountOut, maxAmountsIn, {from: admin});

    assert.equal((await pool.balanceOf.call(admin)).toString(), toWei('200'));

  });

  it('Exit pool after the blocking time has expired', async () => {
    await advanceBlock(3);
    let poolAmountIn = toWei('100');
    let minAmountsOut = [toWei('0'), toWei('4500000'), toWei('100')];
    await pool.exitPool(poolAmountIn, minAmountsOut, {from: admin});
    assert.equal((await pool.balanceOf.call(admin)).toString(), toWei('100'));
  });

  it('Join using tx.origin and a Proxy', async () => {
    let maxAmountsIn = [toWei('1500'), toWei('4500000'), toWei('100')];
    let poolAmountOut = toWei('100');

    let proxy = await TProxy.new();

    await weth.approve(proxy.address, MAX, {from: admin});
    await dai.approve(proxy.address, MAX, {from: admin});
    await wbtc.approve(proxy.address, MAX, {from: admin});

    await proxy.proxyJoinPool(POOL, poolAmountOut, maxAmountsIn, {from: admin});

    assert.equal((await pool.balanceOf.call(admin)).toString(), toWei('200'));
  });

  it('Fail when trying to exit right after a join', async () => {
    let poolAmountOut = toWei('100');
    let maxAmountsIn = [toWei('1500'), toWei('4500000'), toWei('100')];

    // The funds will be taken from the caller
    await pool.joinPool(poolAmountOut, maxAmountsIn, {from: admin});

    let poolAmountIn = toWei('5');
    let minAmountsOut = [toWei('0'), toWei('0'), toWei('0')];

    await truffleAssert.reverts(
        pool.exitPool(poolAmountIn, minAmountsOut, {from: admin}),
        "17",
    );
  });
  
  it('Fail when transfering LP tokens after a join', async () => {
    let poolAmountOut = toWei('100');
    let maxAmountsIn = [toWei('1500'), toWei('4500000'), toWei('100')];

    // The funds will be taken from the caller
    await pool.joinPool(poolAmountOut, maxAmountsIn, {from: admin});
    
    await truffleAssert.reverts(
        pool.transfer(user1, toWei('100'), {from: admin}),
        "17",
    );
  });
  
});