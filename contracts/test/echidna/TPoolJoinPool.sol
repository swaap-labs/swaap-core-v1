// SPDX-License-Identifier: GPL-3.0-or-later

import "../../Num.sol";

pragma solidity =0.8.12;

contract TPoolJoinPool {

    bool public echidna_no_bug_found = true;

    // joinPool models the Pool.joinPool behavior for one token
    // A bug is found if poolAmountOut is greater than 0
    // And tokenAmountIn is 0
    function joinPool(uint poolAmountOut, uint poolTotal, uint _records_t_balance)
        public returns(uint)
    {
        // We constraint poolTotal and _records_t_balance
        // To have "realistic" values
        require(poolTotal <= 100 ether);
        require(poolTotal >= 1 ether);
        require(_records_t_balance <= 10 ether);
        require(_records_t_balance >= 10**6);

        uint ratio = Num.div(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        uint bal = _records_t_balance;
        uint tokenAmountIn = Num.mul(ratio, bal);

        require(poolAmountOut > 0);
        require(tokenAmountIn == 0);

        echidna_no_bug_found = false;

        return tokenAmountIn;
    }

}