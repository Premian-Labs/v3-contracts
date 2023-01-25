// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {OptionMath} from "../libraries/OptionMath.sol";
import {VolatilityOracleStorage} from "./VolatilityOracleStorage.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";


/**
 * @title Premia volatility surface oracle contract for liquid markets.
 */
contract VolatilityOracle is IVolatilityOracle, OwnableInternal {
    using VolatilityOracleStorage for VolatilityOracleStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant DECIMALS = 12;

    event UpdateParameters(
        address indexed base,
        address indexed underlying,
        bytes32 maturities,
        bytes32 theta,
        bytes32 psi,
        bytes32 rho
    );

    struct Params59x18 {
        int128[] maturities;
        int128[] theta;
        int128[] psi;
        int128[] rho;
    }

    struct TotalImpliedVarInfo {
        int128 theta;
        int128 psi;
        int128 rho;
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function formatParams(int256[5] memory params)
    external
    pure
    returns (bytes32 result)
    {
        return VolatilityOracleStorage.formatParams(params);
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function parseParams(bytes32 input)
    external
    pure
    returns (int256[] memory params)
    {
        return VolatilityOracleStorage.parseParams(input);
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getWhitelistedRelayers() external view returns (address[] memory) {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

        uint256 length = l.whitelistedRelayers.length();
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = l.whitelistedRelayers.at(i);
        }

        return result;
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getParams(address base, address underlying)
    external
    view
    returns (VolatilityOracleStorage.Update memory)
    {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        return l.parameters[base][underlying];
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getParamsUnpacked(address base, address underlying)
    external
    view
    returns (VolatilityOracleStorage.Params memory)
    {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        VolatilityOracleStorage.Update memory packed = l.getParams(
            base,
            underlying
        );

        VolatilityOracleStorage.Params memory params = VolatilityOracleStorage.Params({
            maturities: VolatilityOracleStorage.parseParams(packed.maturities),
            theta: VolatilityOracleStorage.parseParams(packed.theta),
            psi: VolatilityOracleStorage.parseParams(packed.psi),
            rho: VolatilityOracleStorage.parseParams(packed.rho)
        });

        return params;
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getTimeToMaturity64x64(uint64 maturity)
    external
    view
    returns (int128) {
        return ABDKMath64x64.divu(maturity - block.timestamp, 365 days);
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) external view returns (int128) {
        return
        _getAnnualizedVolatility64x64(
            base,
            underlying,
            spot64x64,
            strike64x64,
            timeToMaturity64x64
        );
    }

    /**
     * @notice see getAnnualizedVolatility64x64(address,address,int128,int128,int128)
     * @dev deprecated - will be removed once PoolInternal call is updated
     */
    function getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool
    ) external view returns (int128) {
        return
        _getAnnualizedVolatility64x64(
            base,
            underlying,
            spot64x64,
            strike64x64,
            timeToMaturity64x64
        );
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getBlackScholesPrice64x64(
        address base,
        address underlying,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (int128) {
        return
        _getBlackScholesPrice64x64(
            base,
            underlying,
            strike64x64,
            spot64x64,
            timeToMaturity64x64,
            isCall
        );
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getBlackScholesPrice(
        address base,
        address underlying,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (uint256) {
        return
        _getBlackScholesPrice64x64(
            base,
            underlying,
            strike64x64,
            spot64x64,
            timeToMaturity64x64,
            isCall
        ).mulu(10**18);
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function addWhitelistedRelayers(address[] memory accounts)
    external
    onlyOwner
    {
        LiquidOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            l.whitelistedRelayers.add(accounts[i]);
        }
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function removeWhitelistedRelayers(address[] memory accounts)
    external
    onlyOwner
    {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            l.whitelistedRelayers.remove(accounts[i]);
        }
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function updateParams(
        address[] memory base,
        address[] memory underlying,
        bytes32[] memory maturities,
        bytes32[] memory theta,
        bytes32[] memory psi,
        bytes32[] memory rho
    ) external {
        uint256 length = base.length;
        require(
            length == underlying.length &&
            length == maturities.length &&
            length == theta.length &&
            length == psi.length &&
            length == rho.length,
            "Wrong array length"
        );

        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

        require(
            l.whitelistedRelayers.contains(msg.sender),
            "Relayer not whitelisted"
        );

        for (uint256 i = 0; i < length; i++) {
            l.parameters[base[i]][underlying[i]] = VolatilityOracleStorage.Update({
            updatedAt: block.timestamp,
            maturities: maturities[i],
            theta: theta[i],
            psi: psi[i],
            rho: rho[i]
            });

            emit UpdateParameters(
                base[i],
                underlying[i],
                maturities[i],
                theta[i],
                psi[i],
                rho[i]
            );
        }
    }

    /**
     * @notice convert decimal parameter to 64x64 fixed point representation
     * @param value parameter to convert
     * @return 64x64 fixed point representation of parameter
     */
    function _toParameter64x64(int256 value) private pure returns (int128) {
        return ABDKMath64x64.divi(value, int256(10**DECIMALS));
    }

    /**
     * @notice Finds the interval a particular value is located in.
     * @param arr The array of cutoff points that define the intervals
     * @param value The value to find the interval for
     * @return uint256 The interval index that corresponds the value
     */
    function findInterval(int128[] memory arr, int128 value)
    public
    pure
    returns (uint256)
    {
        uint256 low = 0;
        uint256 high = arr.length;
        uint256 m;

        while ((high - low) > 1) {
            m = (uint256)((low + high) / 2);

            if (arr[m] <= value) {
                low = m;
            } else {
                high = m;
            }
        }

        if (arr[low] <= value) {
            return low;
        }
    }

    /**
     * @notice convert a int256[] array to a int128 array
     * @param src The int256[] array to be converted
     * @return int128[] The input array converted to a int128[] array
     */
    function toArray64x64(int256[] memory src)
    private
    pure
    returns (int128[] memory)
    {
        int128[] memory tgt = new int128[](src.length);
        for (uint256 i = 0; i < src.length; i++) {
            tgt[i] = _toParameter64x64(src[i]);
        }
        return tgt;
    }

    /**
     * @notice calculate the annualized volatility for given set of parameters
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param spot64x64 64x64 fixed point representation of spot price
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
     * @return 64x64 fixed point representation of annualized implied volatility, where 1 is defined as 100%
     */
    function _getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) private view returns (int128) {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        VolatilityOracleStorage.Update memory packed = l.getParams(
            base,
            underlying
        );

        Params59x18 memory params = Params59x18({
            maturities: toArray64x64(
                    VolatilityOracleStorage.parseParams(packed.maturities)
                ),
            theta: toArray64x64(VolatilityOracleStorage.parseParams(packed.theta)),
            psi: toArray64x64(VolatilityOracleStorage.parseParams(packed.psi)),
            rho: toArray64x64(VolatilityOracleStorage.parseParams(packed.rho))
        });
        // Number of maturities
        uint256 n = params.maturities.length;

        // Log moneyness
        int128 k = spot64x64.div(strike64x64).ln();

        // Compute total implied variance
        TotalImpliedVarInfo memory info;
        int128 lam;
        int128 one = int128(1 << 64);

        // Short-Term Extrapolation
        if (timeToMaturity64x64 < params.maturities[0]) {
            lam = timeToMaturity64x64.div(params.maturities[0]);

            info = TotalImpliedVarInfo({
                theta: lam.mul(params.theta[0]),
                psi: lam.mul(params.psi[0]),
                rho: params.rho[0]
            });
        }
        // Long-term extrapolation
        else if (timeToMaturity64x64 >= params.maturities[n - 1]) {
            int128 u = int128(2 << 64).div(int128(3 << 64));
            u = u.mul(timeToMaturity64x64 - params.maturities[n - 1]);

            info = TotalImpliedVarInfo({
                theta: params.theta[n - 1] + u,
                psi: params.psi[n - 1],
                rho: params.rho[n - 1]
            });
        } else {
            uint256 i = findInterval(params.maturities, timeToMaturity64x64);
            int128 rho_psi;

            lam = timeToMaturity64x64 - params.maturities[i];
            lam = lam.div(params.maturities[i + 1] - params.maturities[i]);

            info = TotalImpliedVarInfo({
                theta: (one - lam).mul(params.theta[i]) +
                    lam.mul(params.theta[i + 1]),
                psi: (one - lam).mul(params.psi[i]) +
                    lam.mul(params.psi[i + 1]),
                rho: int128(0 << 64)
            });

            rho_psi = (one - lam).mul(params.rho[i]).mul(params.psi[i]);
            rho_psi += lam.mul(params.rho[i + 1]).mul(params.psi[i + 1]);
            info.rho = rho_psi.div(info.psi);
        }

        int128 phi = info.psi.div(info.theta);
        int128 term = (phi.mul(k) + info.rho).pow(2) + (one - info.rho.pow(2));

        int128 w = info.theta.div(int128(2 << 64));
        w = w.mul(one + info.rho.mul(phi).mul(k) + term.sqrt());

        return w.div(timeToMaturity64x64).sqrt();
    }

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param strike64x64 Strike, as a64x64 fixed point representation
     * @param spot64x64 Spot price, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
     * @param isCall Whether it is for call or put
     * @return 64x64 fixed point representation of the Black Scholes price
     */
    function _getBlackScholesPrice64x64(
        address base,
        address underlying,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) private view returns (int128) {
        int128 annualizedVol = _getAnnualizedVolatility64x64(
            base,
            underlying,
            strike64x64,
            spot64x64,
            timeToMaturity64x64
        );
        int128 annualizedVar = annualizedVol.mul(annualizedVol);

        return
        OptionMath._blackScholesPrice(
            annualizedVar,
            strike64x64,
            spot64x64,
            timeToMaturity64x64,
            isCall
        );
    }
}
