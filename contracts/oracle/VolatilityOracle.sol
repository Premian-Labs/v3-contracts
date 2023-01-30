// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;


import {SD59x18, wrap, unwrap} from "@prb/math/src/SD59x18.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

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
        address indexed token,
        bytes32 tau,
        bytes32 theta,
        bytes32 psi,
        bytes32 rho
    );

    struct Params59x18 {
        SD59x18[] tau;
        SD59x18[] theta;
        SD59x18[] psi;
        SD59x18[] rho;
    }

    struct SliceInfo {
        SD59x18 theta;
        SD59x18 psi;
        SD59x18 rho;
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
    function getParams(address token)
    external
    view
    returns (VolatilityOracleStorage.Update memory)
    {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        return l.parameters[token];
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getParamsUnpacked(address token)
    external
    view
    returns (VolatilityOracleStorage.Params memory)
    {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        VolatilityOracleStorage.Update memory packed = l.getParams(token);
        VolatilityOracleStorage.Params memory params = VolatilityOracleStorage.Params({
            tau: VolatilityOracleStorage.parseParams(packed.tau),
            theta: VolatilityOracleStorage.parseParams(packed.theta),
            psi: VolatilityOracleStorage.parseParams(packed.psi),
            rho: VolatilityOracleStorage.parseParams(packed.rho)
        });
        return params;
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getTimeToMaturity(uint64 maturity)
    external
    view
    returns (int256) {
        SD59x18 tau = wrap(int256(maturity - block.timestamp));
        SD59x18 year = wrap(365 days);
        return unwrap(tau.div(year));
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function getVolatility(
        address token,
        int256 spot,
        int256 strike,
        int256 timeToMaturity
    ) external view returns (int256) {
        SD59x18 sigma = _getVolatility59x18(
            token,
            wrap(spot),
            wrap(strike),
            wrap(timeToMaturity)
        );
        return unwrap(sigma);
    }

    /**
     * @inheritdoc IVolatilityOracle
     */
    function addWhitelistedRelayers(address[] memory accounts)
    external
    onlyOwner
    {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

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
        address[] memory tokens,
        bytes32[] memory tau,
        bytes32[] memory theta,
        bytes32[] memory psi,
        bytes32[] memory rho
    ) external {
        uint256 length = tokens.length;
        require(
            length == tokens.length &&
            length == tau.length &&
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
            l.parameters[tokens[i]] = VolatilityOracleStorage.Update({
                updatedAt: block.timestamp,
                tau: tau[i],
                theta: theta[i],
                psi: psi[i],
                rho: rho[i]
            });

            emit UpdateParameters(
                tokens[i],
                tau[i],
                theta[i],
                psi[i],
                rho[i]
            );
        }
    }

    /**
     * @notice Finds the interval a particular value is located in.
     * @param arr SD59x18[] The array of cutoff points that define the intervals
     * @param value SD59x18 The value to find the interval for
     * @return uint256 The interval index that corresponds the value
     */
    function findInterval(SD59x18[] memory arr, SD59x18 value)
    public
    pure
    returns (uint256)
    {
        uint256 low = 0;
        uint256 high = arr.length;
        uint256 m;

        while ((high - low) > 1) {
            m = (uint256)((low + high) / 2);

            if (arr[m].lte(value)) {
                low = m;
            } else {
                high = m;
            }
        }

        if (arr[low].lte(value)) {
            return low;
        }
    }

    /**
     * @notice convert a int256[] array to a int128 array
     * @param src The int256[] array to be converted
     * @return SD59x18[] The input array converted to a SD59x18[] array
     */
    function toArray59x18(int256[] memory src)
    private
    pure
    returns (SD59x18[] memory)
    {
        SD59x18[] memory tgt = new SD59x18[](src.length);
        for (uint256 i = 0; i < src.length; i++) {
            // Covert parameters in DECIMALS to an SD59x18
            tgt[i] = wrap(src[i] * 1e6);
        }
        return tgt;
    }

    function weightedAvg(SD59x18 lam, SD59x18 value1, SD59x18 value2)
    private
    pure
    returns (SD59x18) {
        return (wrap(1e18).sub(lam).mul(value1)).add(lam.mul(value2));
    }

    /**
     * @notice calculate the annualized volatility for given set of parameters
     * @param token The base token of the pair
     * @param spot59x18 59x18 fixed point representation of spot price
     * @param strike59x18 59x18 fixed point representation of strike price
     * @param timeToMaturity59x18 59x18 fixed point representation of time to maturity (denominated in years)
     * @return 59x18 fixed point representation of annualized implied volatility, where 1 is defined as 100%
     */
    function _getVolatility59x18(
        address token,
        SD59x18 spot59x18,
        SD59x18 strike59x18,
        SD59x18 timeToMaturity59x18
    ) private view returns (SD59x18) {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        VolatilityOracleStorage.Update memory packed = l.getParams(token);

        Params59x18 memory params = Params59x18({
            tau: toArray59x18(
                    VolatilityOracleStorage.parseParams(packed.tau)
                ),
            theta: toArray59x18(VolatilityOracleStorage.parseParams(packed.theta)),
            psi: toArray59x18(VolatilityOracleStorage.parseParams(packed.psi)),
            rho: toArray59x18(VolatilityOracleStorage.parseParams(packed.rho))
        });

        // Number of tau
        uint256 n = params.tau.length;

        // Log Moneyness
        SD59x18 k = strike59x18.div(spot59x18).ln();

        // Compute total implied variance
        SliceInfo memory info;
        SD59x18 lam;
        SD59x18 one = wrap(1e18);
        SD59x18 two = wrap(2e18);

        // Short-Term Extrapolation
        if (timeToMaturity59x18.lt(params.tau[0])) {
            lam = timeToMaturity59x18.div(params.tau[0]);

            info = SliceInfo({
                theta: lam.mul(params.theta[0]),
                psi: lam.mul(params.psi[0]),
                rho: params.rho[0]
            });
        }
        // Long-term extrapolation
        else if (timeToMaturity59x18.gte(params.tau[n - 1])) {
            SD59x18 u = timeToMaturity59x18.sub(params.tau[n - 1]);
            u = u.mul(params.theta[n - 1].sub(params.theta[n - 2]));
            u = u.div(params.tau[n - 1].sub(params.tau[n - 2]));

            info = SliceInfo({
                theta: params.theta[n - 1].add(u),
                psi: params.psi[n - 1],
                rho: params.rho[n - 1]
            });
        }
        // Interpolation between tau[0] to tau[n - 1]
        else {
            uint256 i = findInterval(params.tau, timeToMaturity59x18);

            lam = timeToMaturity59x18.sub(params.tau[i]);
            lam = lam.div(params.tau[i + 1].sub(params.tau[i]));

            info = SliceInfo({
                theta: weightedAvg(lam, params.theta[i], params.theta[i + 1]),
                psi: weightedAvg(lam, params.psi[i], params.psi[i + 1]),
                rho: wrap(0)
            });
            info.rho = weightedAvg(
                lam,
                params.rho[i].mul(params.psi[i]),
                params.rho[i + 1].mul(params.psi[i + 1])
            ).div(info.psi);
        }

        SD59x18 phi = info.psi.div(info.theta);
        SD59x18 term = (phi.mul(k).add(info.rho)).pow(two).add(one.sub(info.rho.pow(two)));
        SD59x18 w = info.theta.div(two);
        w = w.mul(one.add(info.rho.mul(phi).mul(k)).add(term.sqrt()));

        return w.div(timeToMaturity59x18).sqrt();
    }

}