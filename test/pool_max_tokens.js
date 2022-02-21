const truffleAssert = require('truffle-assertions');

const Pool = artifacts.require('Pool');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const TConstantOracle = artifacts.require('TConstantOracle');

contract('Pool', async (accounts) => {
    const admin = accounts[0];

    const now = 1641893000;

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    let AAA; let BBB; let CCC; let DDD; let EEE; let FFF; let GGG; let HHH; let
        ZZZ; // addresses
    let aaa; let bbb; let ccc; let ddd; let eee; let fff; let ggg; let hhh; let
        zzz; // TTokens
    let aaaOracle; let bbbOracle; let cccOracle; let dddOracle; let eeeOracle; let fffOracle; let gggOracle; let hhhOracle; let
        zzzOracle; // TTokens
    let aaaOracleAddress; let bbbOracleAddress; let cccOracleAddress; let dddOracleAddress; let eeeOracleAddress;
    	let fffOracleAddress; let gggOracleAddress; let hhhOracleAddress; let zzzOracleAddress; // TTokens
    let factory; // Pool factory
    let FACTORY; // factory address
    let pool; // first pool w/ defaults
    let POOL; //   pool address

    before(async () => {
        factory = await Factory.deployed();
        FACTORY = factory.address;

        POOL = await factory.newPool.call();
        await factory.newPool();
        pool = await Pool.at(POOL);

        aaa = await TToken.new('AAA', 'AAA', 18);
        bbb = await TToken.new('BBB', 'BBB', 18);
        ccc = await TToken.new('CCC', 'CCC', 18);
        ddd = await TToken.new('DDD', 'EEE', 18);
        eee = await TToken.new('EEE', 'EEE', 18);
        fff = await TToken.new('FFF', 'FFF', 18);
        ggg = await TToken.new('GGG', 'GGG', 18);
        hhh = await TToken.new('HHH', 'HHH', 18);
        zzz = await TToken.new('ZZZ', 'ZZZ', 18);

		aaaOracle = await TConstantOracle.new(4200000000, now);
		aaaOracleAddress = aaaOracle.address
		bbbOracleAddress = aaaOracleAddress
		cccOracleAddress = aaaOracleAddress
		dddOracleAddress = aaaOracleAddress
		eeeOracleAddress = aaaOracleAddress
		fffOracleAddress = aaaOracleAddress
		gggOracleAddress = aaaOracleAddress
		hhhOracleAddress = aaaOracleAddress
		zzzOracleAddress = aaaOracleAddress

        AAA = aaa.address;
        BBB = bbb.address;
        CCC = ccc.address;
        DDD = ddd.address;
        EEE = eee.address;
        FFF = fff.address;
        GGG = ggg.address;
        HHH = hhh.address;
        ZZZ = zzz.address;

        // Admin balances
        await aaa.mint(admin, toWei('100'));
        await bbb.mint(admin, toWei('100'));
        await ccc.mint(admin, toWei('100'));
        await ddd.mint(admin, toWei('100'));
        await eee.mint(admin, toWei('100'));
        await fff.mint(admin, toWei('100'));
        await ggg.mint(admin, toWei('100'));
        await hhh.mint(admin, toWei('100'));
        await zzz.mint(admin, toWei('100'));
    });

    describe('Binding Tokens', () => {
        it('Admin approves tokens', async () => {
            await aaa.approve(POOL, MAX);
            await bbb.approve(POOL, MAX);
            await ccc.approve(POOL, MAX);
            await ddd.approve(POOL, MAX);
            await eee.approve(POOL, MAX);
            await fff.approve(POOL, MAX);
            await ggg.approve(POOL, MAX);
            await hhh.approve(POOL, MAX);
            await zzz.approve(POOL, MAX);
        });

        it('Admin binds tokens', async () => {
            await pool.bindMMM(AAA, toWei('50'), toWei('1'), aaaOracleAddress);
            await pool.bindMMM(BBB, toWei('50'), toWei('3'), bbbOracleAddress);
            await pool.bindMMM(CCC, toWei('50'), toWei('2.5'), cccOracleAddress);
            await pool.bindMMM(DDD, toWei('50'), toWei('7'), dddOracleAddress);
            await pool.bindMMM(EEE, toWei('50'), toWei('10'), eeeOracleAddress);
            await pool.bindMMM(FFF, toWei('50'), toWei('1.99'), fffOracleAddress);
            await pool.bindMMM(GGG, toWei('40'), toWei('6'), gggOracleAddress);
            await pool.bindMMM(HHH, toWei('70'), toWei('2.3'), hhhOracleAddress);

            const totalDernomWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(33.79, fromWei(totalDernomWeight));
        });

        it('Fails binding more than 8 tokens', async () => {
            await truffleAssert.reverts(pool.bindMMM(ZZZ, toWei('50'), toWei('2'), zzzOracleAddress), 'ERR_MAX_TOKENS');
        });

        it('Rebind token at a smaller balance', async () => {
            await pool.rebindMMM(HHH, toWei('50'), toWei('2.1'), hhhOracleAddress);
            const balance = await pool.getBalance(HHH);
            assert.equal(fromWei(balance), 50);

            const adminBalance = await hhh.balanceOf(admin);
            assert.equal(fromWei(adminBalance), 50);

            const factoryBalance = await hhh.balanceOf(FACTORY);
            assert.equal(fromWei(factoryBalance), 0);

            const totalDernomWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(33.59, fromWei(totalDernomWeight));
        });

        it('Fails gulp on unbound token', async () => {
            await truffleAssert.reverts(pool.gulp(ZZZ), 'ERR_NOT_BOUND');
        });

        it('Pool can gulp tokens', async () => {
            await ggg.transferFrom(admin, POOL, toWei('10'));

            await pool.gulp(GGG);
            const balance = await pool.getBalance(GGG);
            assert.equal(fromWei(balance), 50);
        });

        it('Fails swapExactAmountIn with limits', async () => {
            await pool.setPublicSwap(true);
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(
                    AAA,
                    toWei('1'),
                    BBB,
                    toWei('0'),
                    toWei('0.9'),
                ),
                'ERR_BAD_LIMIT_PRICE',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(
                    AAA,
                    toWei('1'),
                    BBB,
                    toWei('2'),
                    toWei('3.5'),
                ),
                'ERR_LIMIT_OUT',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountInMMM(
                    AAA,
                    toWei('1'),
                    BBB,
                    toWei('0'),
                    toWei('3.00001'),
                ),
                'ERR_LIMIT_PRICE',
            );
        });

        it('Fails swapExactAmountOutMMM with limits', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(
                    AAA,
                    toWei('51'),
                    BBB,
                    toWei('40'),
                    toWei('5'),
                ),
                'ERR_MAX_OUT_RATIO',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(
                    AAA,
                    toWei('5'),
                    BBB,
                    toWei('1'),
                    toWei('1'),
                ),
                'ERR_BAD_LIMIT_PRICE',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(
                    AAA,
                    toWei('1'),
                    BBB,
                    toWei('1'),
                    toWei('5'),
                ),
                'ERR_LIMIT_IN',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOutMMM(
                    AAA,
                    toWei('5'),
                    BBB,
                    toWei('1'),
                    toWei('3.00001'),
                ),
                'ERR_LIMIT_PRICE',
            );
        });
    });
});
