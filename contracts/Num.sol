// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity =0.8.0;

import "./Const.sol";

library Num {

    function btoi(uint256 a)
        public pure
        returns (uint256)
    {
        return a / Const.BONE;
    }

    function bfloor(uint256 a)
        public pure
        returns (uint256)
    {
        return btoi(a) * Const.BONE;
    }

    function badd(uint256 a, uint256 b)
        public pure
        returns (uint256)
    {
        uint256 c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function bsub(uint256 a, uint256 b)
        public pure
        returns (uint256)
    {
        (uint256 c, bool flag) = bsubSign(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    function bsubSign(uint256 a, uint256 b)
        public pure
        returns (uint256, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function bmul(uint256 a, uint256 b)
        public pure
        returns (uint256)
    {
        uint256 c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint256 c1 = c0 + (Const.BONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint256 c2 = c1 / Const.BONE;
        return c2;
    }

    function bdiv(uint256 a, uint256 b)
        public pure
        returns (uint256)
    {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * Const.BONE;
        require(a == 0 || c0 / a == Const.BONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    // DSMath.wpow
    function bpowi(uint256 a, uint256 n)
        public pure
        returns (uint256)
    {
        uint256 z = n % 2 != 0 ? a : Const.BONE;

        for (n /= 2; n != 0; n /= 2) {
            a = bmul(a, a);

            if (n % 2 != 0) {
                z = bmul(z, a);
            }
        }
        return z;
    }

    // Compute b^(e.w) by splitting it into (b^e)*(b^0.w).
    // Use `bpowi` for `b^e` and `bpowK` for k iterations
    // of approximation of b^0.w
    function bpow(uint256 base, uint256 exp)
        public pure
        returns (uint256)
    {
        require(base >= Const.MIN_BPOW_BASE, "ERR_BPOW_BASE_TOO_LOW");
        require(base <= Const.MAX_BPOW_BASE, "ERR_BPOW_BASE_TOO_HIGH");

        uint256 whole  = bfloor(exp);
        uint256 remain = bsub(exp, whole);

        uint256 wholePow = bpowi(base, btoi(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint256 partialResult = bpowApprox(base, remain, Const.BPOW_PRECISION);
        return bmul(wholePow, partialResult);
    }

    function bpowApprox(uint256 base, uint256 exp, uint256 precision)
        public pure
        returns (uint256)
    {
        // term 0:
        uint256 a     = exp;
        (uint256 x, bool xneg)  = bsubSign(base, Const.BONE);
        uint256 term = Const.BONE;
        uint256 sum   = term;
        bool negative = false;


        // term(k) = numer / denom 
        //         = (product(a - i - 1, i=1-->k) * x^k) / (k!)
        // each iteration, multiply previous term by (a-(k-1)) * x / k
        // continue until term is less than precision
        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * Const.BONE;
            (uint256 c, bool cneg) = bsubSign(a, bsub(bigK, Const.BONE));
            term = bmul(term, bmul(c, x));
            term = bdiv(term, bigK);
            if (term == 0) break;

            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = bsub(sum, term);
            } else {
                sum = badd(sum, term);
            }
        }

        return sum;
    }

    /**
    * @notice Computes the division of 2 int256 with BONE precision
    * @dev Converts inputs to uint256 if needed, and then uses bdiv(uint256, uint256)
    * @param a The int256 representation of a floating point number with BONE precision
    * @param b The int256 representation of a floating point number with BONE precision
    * @return b The division of 2 int256 with BONE precision
    */
    function bdivInt256(int256 a, int256 b) public pure returns (int256) {
        if (a < 0) {
            if (b < 0) {
                return int256(bdiv(uint256(-a), uint256(-b))); // both negative
            } else {
                return -int256(bdiv(uint256(-a), uint256(b))); // a < 0, b >= 0
            }
        } else {
            if (b < 0) {
                return -int256(bdiv(uint256(a), uint256(-b))); // a >= 0, b < 0
            } else {
                return int256(bdiv(uint256(a), uint256(b))); // both positive
            }
        }
    }


}
