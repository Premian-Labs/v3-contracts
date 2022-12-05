// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Fraction {
    uint256 internal constant WAD = 1e18;

    struct F256 {
        uint128 n;
        uint128 d;
    }

    struct F512 {
        uint256 n;
        uint256 d;
    }

    function toF512(F256 memory a) internal pure returns (F512 memory) {
        return F512(a.n, a.d);
    }

    function toF256(F512 memory a) internal pure returns (F256 memory) {
        return F256(uint128(a.n), uint128(a.d));
    }

    function add(
        F512 memory a,
        F512 memory b
    ) internal pure returns (F512 memory) {
        uint256 g1 = gcd(a.d, b.d);
        if (g1 == 1) return F512(a.n * b.d + a.d * b.n, a.d * b.d);

        uint256 s = a.d / g1;
        uint256 t = a.n * (b.d / g1) + b.n * s;
        uint256 g2 = gcd(t, g1);

        if (g2 == 1) return F512(t, s * b.d);

        return F512(t / g2, s * (b.d / g2));
    }

    function sub(
        F512 memory a,
        F512 memory b
    ) internal pure returns (F512 memory) {
        uint256 g1 = gcd(a.d, b.d);
        if (g1 == 1) return F512(a.n * b.d - a.d * b.n, a.d * b.d);

        uint256 s = a.d / g1;
        uint256 t = a.n * (b.d / g1) - b.n * s;
        uint256 g2 = gcd(t, g1);
        if (g2 == 1) return F512(t, s * b.d);
        return F512(t / g2, s * (b.d / g2));
    }

    function mul(
        F512 memory a,
        F512 memory b
    ) internal pure returns (F512 memory) {
        uint256 g = gcd(a.n, b.d);
        if (g > 1) {
            a.n /= g;
            b.d /= g;
        }

        g = gcd(b.n, a.d);
        if (g > 1) {
            b.n /= g;
            a.d /= g;
        }

        return F512(a.n * b.n, a.d * b.d);
    }

    function mulWad(
        F512 memory a,
        F512 memory b
    ) internal pure returns (F512 memory) {
        F512 memory r = mul(a, b);
        r.n /= WAD;

        return r;
    }

    function div(
        F512 memory a,
        F512 memory b
    ) internal pure returns (F512 memory) {
        uint256 g = gcd(a.n, b.n);
        if (g > 1) {
            a.n /= g;
            b.n /= g;
        }

        g = gcd(b.d, a.d);
        if (g > 1) {
            b.d /= g;
            a.d /= g;
        }

        return F512(a.n * b.d, b.n * a.d);
    }

    function divWad(
        F512 memory a,
        F512 memory b
    ) internal pure returns (F512 memory) {
        a.n *= WAD;
        return div(a, b);
    }

    function gcd(uint256 a, uint256 b) internal pure returns (uint256 r) {
        assembly {
            for {

            } gt(b, 0) {

            } {
                let t := b
                b := mod(a, b)
                a := t
            }

            r := a
        }
    }
}
