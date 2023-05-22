// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IVolatilityOracle} from "./IVolatilityOracle.sol";
import {VolatilityOracleStorage} from "./VolatilityOracleStorage.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {ZERO, iZERO, iONE, iTWO} from "../libraries/Constants.sol";
import {PRBMathExtra} from "../libraries/PRBMathExtra.sol";

/// @title Premia volatility surface oracle contract for liquid markets.
contract VolatilityOracle is IVolatilityOracle, OwnableInternal {
    using VolatilityOracleStorage for VolatilityOracleStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for uint256;
    using SafeCast for int256;
    using PRBMathExtra for UD60x18;
    using PRBMathExtra for SD59x18;

    uint256 private constant DECIMALS = 12;

    event UpdateParameters(address indexed token, bytes32 tau, bytes32 theta, bytes32 psi, bytes32 rho);

    struct Params {
        SD59x18[5] tau;
        SD59x18[5] theta;
        SD59x18[5] psi;
        SD59x18[5] rho;
    }

    struct SliceInfo {
        SD59x18 theta;
        SD59x18 psi;
        SD59x18 rho;
    }

    /// @inheritdoc IVolatilityOracle
    function addWhitelistedRelayers(address[] calldata accounts) external onlyOwner {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            l.whitelistedRelayers.add(accounts[i]);
        }
    }

    /// @inheritdoc IVolatilityOracle
    function removeWhitelistedRelayers(address[] calldata accounts) external onlyOwner {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            l.whitelistedRelayers.remove(accounts[i]);
        }
    }

    /// @inheritdoc IVolatilityOracle
    function getWhitelistedRelayers() external view returns (address[] memory) {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

        uint256 length = l.whitelistedRelayers.length();
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = l.whitelistedRelayers.at(i);
        }

        return result;
    }

    /// @inheritdoc IVolatilityOracle
    function formatParams(int256[5] calldata params) external pure returns (bytes32 result) {
        return VolatilityOracleStorage.formatParams(params);
    }

    /// @inheritdoc IVolatilityOracle
    function parseParams(bytes32 input) external pure returns (int256[5] memory params) {
        return VolatilityOracleStorage.parseParams(input);
    }

    /// @inheritdoc IVolatilityOracle
    function updateParams(
        address[] calldata tokens,
        bytes32[] calldata tau,
        bytes32[] calldata theta,
        bytes32[] calldata psi,
        bytes32[] calldata rho,
        UD60x18 riskFreeRate
    ) external {
        if (
            tokens.length != tau.length ||
            tokens.length != theta.length ||
            tokens.length != psi.length ||
            tokens.length != rho.length
        ) revert IVolatilityOracle.VolatilityOracle__ArrayLengthMismatch();

        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();

        if (!l.whitelistedRelayers.contains(msg.sender))
            revert IVolatilityOracle.VolatilityOracle__RelayerNotWhitelisted(msg.sender);

        for (uint256 i = 0; i < tokens.length; i++) {
            l.parameters[tokens[i]] = VolatilityOracleStorage.Update({
                updatedAt: block.timestamp,
                tau: tau[i],
                theta: theta[i],
                psi: psi[i],
                rho: rho[i]
            });

            emit UpdateParameters(tokens[i], tau[i], theta[i], psi[i], rho[i]);
        }

        l.riskFreeRate = riskFreeRate;
    }

    /// @inheritdoc IVolatilityOracle
    function getParams(address token) external view returns (VolatilityOracleStorage.Update memory) {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        return l.parameters[token];
    }

    /// @inheritdoc IVolatilityOracle
    function getParamsUnpacked(address token) external view returns (VolatilityOracleStorage.Params memory) {
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

    /// @notice Finds the interval a particular value is located in.
    /// @param arr The array of cutoff points that define the intervals
    /// @param value The value to find the interval for
    /// @return The interval index that corresponds the value
    function _findInterval(SD59x18[5] memory arr, SD59x18 value) internal pure returns (uint256) {
        uint256 low = 0;
        uint256 high = arr.length;
        uint256 m;
        uint256 result;

        while ((high - low) > 1) {
            m = (uint256)((low + high) / 2);

            if (arr[m] <= value) {
                low = m;
            } else {
                high = m;
            }
        }

        if (arr[low] <= value) {
            result = low;
        }

        return result;
    }

    /// @notice Convert an int256[] array to a SD59x18[] array
    /// @param src The array to be converted
    /// @return tgt The input array converted to a SD59x18[] array
    function _toArray59x18(int256[5] memory src) internal pure returns (SD59x18[5] memory tgt) {
        for (uint256 i = 0; i < src.length; i++) {
            // Convert parameters in DECIMALS to an SD59x18
            tgt[i] = sd(src[i] * 1e6);
        }
        return tgt;
    }

    function _weightedAvg(SD59x18 lam, SD59x18 value1, SD59x18 value2) internal pure returns (SD59x18) {
        return (iONE - lam) * value1 + (lam * value2);
    }

    /// @inheritdoc IVolatilityOracle
    function getVolatility(
        address token,
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity
    ) public view virtual returns (UD60x18) {
        if (spot == ZERO) revert VolatilityOracle__SpotIsZero();
        if (strike == ZERO) revert VolatilityOracle__StrikeIsZero();
        if (timeToMaturity == ZERO) revert VolatilityOracle__TimeToMaturityIsZero();

        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        VolatilityOracleStorage.Update memory packed = l.getParams(token);

        Params memory params = Params({
            tau: _toArray59x18(VolatilityOracleStorage.parseParams(packed.tau)),
            theta: _toArray59x18(VolatilityOracleStorage.parseParams(packed.theta)),
            psi: _toArray59x18(VolatilityOracleStorage.parseParams(packed.psi)),
            rho: _toArray59x18(VolatilityOracleStorage.parseParams(packed.rho))
        });

        // Number of tau
        uint256 n = params.tau.length;

        // Log Moneyness
        SD59x18 k = (strike / spot).intoSD59x18().ln();

        // Compute total implied variance
        SliceInfo memory info;
        SD59x18 lam;

        SD59x18 _timeToMaturity = timeToMaturity.intoSD59x18();

        // Short-Term Extrapolation
        if (_timeToMaturity < params.tau[0]) {
            lam = _timeToMaturity / params.tau[0];

            info = SliceInfo({theta: lam * params.theta[0], psi: lam * params.psi[0], rho: params.rho[0]});
        }
        // Long-term extrapolation
        else if (_timeToMaturity >= params.tau[n - 1]) {
            SD59x18 u = _timeToMaturity - params.tau[n - 1];
            u = u * (params.theta[n - 1] - params.theta[n - 2]);
            u = u / (params.tau[n - 1] - params.tau[n - 2]);

            info = SliceInfo({theta: params.theta[n - 1] + u, psi: params.psi[n - 1], rho: params.rho[n - 1]});
        }
        // Interpolation between tau[0] to tau[n - 1]
        else {
            uint256 i = _findInterval(params.tau, _timeToMaturity);

            lam = _timeToMaturity - params.tau[i];
            lam = lam / (params.tau[i + 1] - params.tau[i]);

            info = SliceInfo({
                theta: _weightedAvg(lam, params.theta[i], params.theta[i + 1]),
                psi: _weightedAvg(lam, params.psi[i], params.psi[i + 1]),
                rho: iZERO
            });
            info.rho =
                _weightedAvg(lam, params.rho[i] * params.psi[i], params.rho[i + 1] * params.psi[i + 1]) /
                info.psi;
        }

        SD59x18 phi = info.psi / info.theta;

        // Use powu(2) instead of pow(TWO) here (o.w. LogInputTooSmall Error)
        SD59x18 term = (phi * k + info.rho).powu(2) + (iONE - info.rho.powu(2));

        SD59x18 w = info.theta / iTWO;
        w = w * (iONE + info.rho * phi * k + term.sqrt());

        return (w / _timeToMaturity).sqrt().intoUD60x18();
    }

    // @inheritdoc IVolatilityOracle
    function getVolatility(
        address token,
        UD60x18 spot,
        UD60x18[] memory strike,
        UD60x18[] memory timeToMaturity
    ) external view virtual returns (UD60x18[] memory) {
        if (strike.length != timeToMaturity.length) revert VolatilityOracle__ArrayLengthMismatch();

        UD60x18[] memory sigma = new UD60x18[](strike.length);

        for (uint256 i = 0; i < sigma.length; i++) {
            sigma[i] = getVolatility(token, spot, strike[i], timeToMaturity[i]);
        }

        return sigma;
    }

    // @inheritdoc IVolatilityOracle
    function getRiskFreeRate() external view virtual returns (UD60x18) {
        VolatilityOracleStorage.Layout storage l = VolatilityOracleStorage.layout();
        return l.riskFreeRate;
    }
}
