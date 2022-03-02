const truffleAssert = require('truffle-assertions');

const TMath = artifacts.require('TMath');

contract('TMath', async () => {
    const MAX = web3.utils.toTwosComplement(-1);

    describe('Math', () => {
        let tmath;
        before(async () => {
            tmath = await TMath.deployed();
        });

        it('bmul throws on overflow', async () => {
            await truffleAssert.reverts(tmath.calc_bmul(2, MAX), 'revert'); // ERR_MUL_OVERFLOW
        });

        it('bdiv throws on div by 0', async () => {
            await truffleAssert.reverts(tmath.calc_bdiv(1, 0), 'revert');
        });

        it('bpow throws on base outside range', async () => {
            await truffleAssert.reverts(tmath.calc_bpow(0, 2), '39');
            await truffleAssert.reverts(tmath.calc_bpow(MAX, 2), '40');
        });
    });
});
