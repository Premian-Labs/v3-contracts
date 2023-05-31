// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {OracleAdapterMock} from "contracts/test/adapter/OracleAdapterMock.sol";
import {VolatilityOracleMock} from "contracts/test/oracle/VolatilityOracleMock.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

import {DeployTest} from "../../../Deploy.t.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {UnderwriterVaultProxy} from "contracts/vault/strategies/underwriter/UnderwriterVaultProxy.sol";
import {IVaultRegistry} from "contracts/vault/IVaultRegistry.sol";

contract UnderwriterVaultDeployTest is DeployTest {
    struct TestVars {
        UD60x18 totalSupply;
        UD60x18 shares;
        UD60x18 pps;
        UD60x18 ppsUser;
        UD60x18 performanceFeeRate;
        UD60x18 managementFeeRate;
        uint256 timeOfDeposit;
        uint256 timestamp;
        UD60x18 protocolFeesInitial;
        UD60x18 netUserDepositReceiver;
        UD60x18 transferAmount;
    }

    uint256 startTime = 100000;

    uint256 t0 = startTime + 7 days;
    uint256 t1 = startTime + 10 days;
    uint256 t2 = startTime + 14 days;
    uint256 t3 = startTime + 30 days;

    bytes32 vaultType;

    address longCall;
    address shortCall;

    VolatilityOracleMock volOracle;

    UnderwriterVaultMock vault;
    UnderwriterVaultMock callVault;
    UnderwriterVaultMock putVault;

    function setUp() public virtual override {
        _setUp(16597500, 1677225600);

        longCall = address(new ERC20Mock("LONG_CALL", 18));
        shortCall = address(new ERC20Mock("SHORT_CALL", 18));

        address[5] memory users = [users.caller, users.receiver, users.underwriter, users.lp, users.trader];

        for (uint256 i; i < users.length; i++) {
            deal(base, users[i], 1_000e18);
            deal(quote, users[i], 1_000_000e6);
        }

        oracleAdapter.setQuote(ud(1500e18));

        volOracle = new VolatilityOracleMock();
        volOracle.setRiskFreeRate(ud(0.01e18));

        volOracle.setVolatility(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            ud(1000e18),
            ud(1100e18),
            ud(38356164383561643),
            ud(1.54e18)
        );

        poolKey.strike = ud(1500e18);

        vaultType = keccak256("UnderwriterVault");

        // Update settings
        uint256[] memory settings = new uint256[](10);

        settings[0] = 3e18;
        settings[1] = 0.005e18;
        settings[2] = 1e18;
        settings[3] = 1.2e18;
        settings[4] = 3e18;
        settings[5] = 30e18;
        settings[6] = 0.1e18;
        settings[7] = 0.7e18;
        settings[8] = 0.05e18;
        settings[9] = 0.02e18;

        vaultRegistry.updateSettings(vaultType, abi.encode(settings));

        // Deploy and set vault implementation
        address vaultImpl = address(
            new UnderwriterVaultMock(
                address(vaultRegistry),
                feeReceiver,
                address(volOracle),
                address(factory),
                address(router),
                address(vxPremia),
                address(diamond)
            )
        );

        vaultRegistry.setImplementation(vaultType, vaultImpl);

        // Deploy vaults
        address callVaultProxy = address(
            new UnderwriterVaultProxy(
                address(vaultRegistry),
                base,
                quote,
                address(oracleAdapter),
                "WETH Call Vault",
                "WETH Call Vault",
                true
            )
        );

        callVault = UnderwriterVaultMock(callVaultProxy);

        vaultRegistry.addVault(
            callVaultProxy,
            base,
            vaultType,
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Call
        );

        address putVaultProxy = address(
            new UnderwriterVaultProxy(
                address(vaultRegistry),
                base,
                quote,
                address(oracleAdapter),
                "WETH Put Vault",
                "WETH Put Vault",
                false
            )
        );

        putVault = UnderwriterVaultMock(putVaultProxy);

        vaultRegistry.addVault(
            putVaultProxy,
            quote,
            vaultType,
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Put
        );
    }

    function setMaturities() internal {
        uint256 minMaturity = block.timestamp + 10 * 1 days;
        uint256 maxMaturity = block.timestamp + 20 * 1 days;

        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](2);
        infos[0].maturity = minMaturity;
        infos[1].maturity = maxMaturity;

        vault.setListingsAndSizes(infos);
    }

    function addDeposit(address user, UD60x18 amount) internal {
        IERC20 token = IERC20(getPoolToken());
        uint256 assetAmount = scaleDecimals(amount);

        vm.startPrank(user);

        token.approve(address(vault), assetAmount);
        vault.deposit(assetAmount, user);

        vm.stopPrank();
    }

    function setup(TestVars memory vars) internal {
        // set pps and totalSupply vault
        vault.increaseTotalShares((vars.totalSupply - vars.shares).unwrap());
        uint256 vaultDeposit = scaleDecimals(vars.pps * vars.totalSupply);

        deal(getPoolToken(), address(vault), vaultDeposit);
        vault.increaseTotalAssets(vars.pps * vars.totalSupply);

        // set pps and shares user
        vault.mintMock(users.caller, vars.shares.unwrap());
        UD60x18 userDeposit = vars.shares * vars.ppsUser;
        vault.setNetUserDeposit(users.caller, userDeposit.unwrap());
        vault.setTimeOfDeposit(users.caller, vars.timeOfDeposit);

        if (vars.shares > ud(0)) {
            uint256 ppsAvg = vault.getAveragePricePerShare(users.caller);
            assertEq(ppsAvg, vars.ppsUser.unwrap());
        }

        assertEq(vault.totalSupply(), vars.totalSupply);
        assertEq(vault.getPricePerShare(), vars.pps);
    }

    function setupGetFeeVars(TestVars memory vars) internal {
        setup(vars);

        vault.setPerformanceFeeRate(vars.performanceFeeRate);
        vault.setManagementFeeRate(vars.managementFeeRate);
    }

    function setupBeforeTokenTransfer(TestVars memory vars) internal {
        setupGetFeeVars(vars);

        uint256 vaultDeposit = scaleDecimals(vars.pps * vars.totalSupply);
        deal(getPoolToken(), address(vault), vaultDeposit + scaleDecimals(vars.protocolFeesInitial));
        vault.setProtocolFees(vars.protocolFeesInitial);
        vault.setNetUserDeposit(users.receiver, vars.netUserDepositReceiver.unwrap());
    }

    // prettier-ignore
    function setupVolOracleMock() internal {
        volOracle.setVolatility(base, ud(1000e18), ud(900e18),  ud(2739726027397260),  ud(0.123e18));
        volOracle.setVolatility(base, ud(1000e18), ud(2000e18), ud(2739726027397260),  ud(0.89e18));
        volOracle.setVolatility(base, ud(1000e18), ud(700e18),  ud(10958904109589041), ud(3.5e18));
        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(10958904109589041), ud(0.034e18));
        volOracle.setVolatility(base, ud(1000e18), ud(800e18),  ud(21917808219178082), ud(2.1e18));
        volOracle.setVolatility(base, ud(1000e18), ud(2000e18), ud(21917808219178082), ud(1.1e18));
        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(65753424657534246), ud(0.99e18));

        volOracle.setVolatility(base, ud(1000e18), ud(700e18),  ud(5479452054794520),  ud(0.512e18));
        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(5479452054794520),  ud(0.034e18));
        volOracle.setVolatility(base, ud(1000e18), ud(800e18),  ud(16438356164383561), ud(2.1e18));
        volOracle.setVolatility(base, ud(1000e18), ud(2000e18), ud(16438356164383561), ud(1.2e18));
        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(60273972602739726), ud(0.9e18));

        volOracle.setVolatility(base, ud(1000e18), ud(700e18),  ud(8219178082191780),  ud(0.512e18));
        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(8219178082191780),  ud(0.034e18));
        volOracle.setVolatility(base, ud(1000e18), ud(800e18),  ud(19178082191780821), ud(2.1e18));
        volOracle.setVolatility(base, ud(1000e18), ud(2000e18), ud(19178082191780821), ud(1.2e18));
        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(63013698630136986), ud(0.9e18));

        volOracle.setVolatility(base, ud(1000e18), ud(800e18),  ud(10958904109589041), ud(1.1e18));
        volOracle.setVolatility(base, ud(1000e18), ud(2000e18), ud(10958904109589041), ud(1.2e18));
        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(54794520547945205), ud(0.9e18));

        volOracle.setVolatility(base, ud(1000e18), ud(800e18),  ud(8219178082191780),  ud(0.512e18));
        volOracle.setVolatility(base, ud(1000e18), ud(2000e18), ud(8219178082191780),  ud(0.034e18));
        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(52054794520547945), ud(0.9e18));

        volOracle.setVolatility(base, ud(1000e18), ud(1500e18), ud(41095890410958904), ud(0.2e18));
    }
}
