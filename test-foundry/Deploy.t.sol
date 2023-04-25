// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {ISolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {InitFeeCalculator} from "contracts/factory/InitFeeCalculator.sol";
import {PoolFactory} from "contracts/factory/PoolFactory.sol";
import {PoolFactoryProxy} from "contracts/factory/PoolFactoryProxy.sol";

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolBase} from "contracts/pool/PoolBase.sol";
import {PoolCore} from "contracts/pool/PoolCore.sol";
import {PoolCoreMock} from "contracts/test/pool/PoolCoreMock.sol";
import {PoolDepositWithdraw} from "contracts/pool/PoolDepositWithdraw.sol";
import {PoolTrade} from "contracts/pool/PoolTrade.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {Premia} from "contracts/proxy/Premia.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {ERC20Router} from "contracts/router/ERC20Router.sol";

import {FlashLoanMock} from "contracts/test/pool/FlashLoanMock.sol";
import {OracleAdapterMock} from "contracts/test/oracle/OracleAdapterMock.sol";

import {Assertions} from "./Assertions.sol";

contract DeployTest is Test, Assertions {
    uint256 mainnetFork;

    address base;
    address quote;
    OracleAdapterMock oracleAdapter;
    IPoolFactory.PoolKey poolKey;
    PoolFactory factory;
    Premia diamond;
    ERC20Router router;

    IPoolMock pool;

    Position.Key posKey;

    IPoolInternal.QuoteRFQ quoteRFQ;

    Users users;

    FlashLoanMock flashLoanMock;

    struct Users {
        address lp;
        address trader;
    }

    bytes4[] internal poolBaseSelectors;
    bytes4[] internal poolCoreMockSelectors;
    bytes4[] internal poolCoreSelectors;
    bytes4[] internal poolDepositWithdrawSelectors;
    bytes4[] internal poolTradeSelectors;

    address public constant feeReceiver =
        address(0x000000000000000000000000000000000000dEaD);

    receive() external payable {}

    function setUp() public virtual {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );
        mainnetFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(mainnetFork);

        users = Users({lp: vm.addr(1), trader: vm.addr(2)});
        base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        quote = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

        oracleAdapter = new OracleAdapterMock(
            address(base),
            address(quote),
            UD60x18.wrap(1000 ether),
            UD60x18.wrap(1000 ether)
        );
        poolKey = IPoolFactory.PoolKey({
            base: base,
            quote: quote,
            oracleAdapter: address(oracleAdapter),
            strike: UD60x18.wrap(1000 ether),
            maturity: 1682668800,
            isCallPool: true
        });

        quoteRFQ = IPoolInternal.QuoteRFQ({
            provider: users.lp,
            taker: address(0),
            price: UD60x18.wrap(0.1 ether),
            size: UD60x18.wrap(10 ether),
            isBuy: false,
            deadline: block.timestamp + 1 hours,
            salt: block.timestamp
        });

        diamond = new Premia();

        InitFeeCalculator initFeeCalculatorImpl = new InitFeeCalculator(
            address(base),
            address(oracleAdapter)
        );

        ProxyUpgradeableOwnable initFeeCalculatorProxy = new ProxyUpgradeableOwnable(
                address(initFeeCalculatorImpl)
            );

        PoolFactory factoryImpl = new PoolFactory(
            address(diamond),
            address(oracleAdapter),
            address(initFeeCalculatorProxy)
        );

        PoolFactoryProxy factoryProxy = new PoolFactoryProxy(
            address(factoryImpl),
            UD60x18.wrap(0.1 ether),
            feeReceiver
        );

        flashLoanMock = new FlashLoanMock();

        factory = PoolFactory(address(factoryProxy));

        router = new ERC20Router(address(factory));

        PoolBase poolBaseImpl = new PoolBase();

        PoolCoreMock poolCoreMockImpl = new PoolCoreMock(
            address(factory),
            address(router),
            address(base),
            feeReceiver
        );

        PoolCore poolCoreImpl = new PoolCore(
            address(factory),
            address(router),
            address(base),
            feeReceiver
        );

        PoolDepositWithdraw poolDepositWithdrawImpl = new PoolDepositWithdraw(
            address(factory),
            address(router),
            address(base),
            feeReceiver
        );

        PoolTrade poolTradeImpl = new PoolTrade(
            address(factory),
            address(router),
            address(base),
            feeReceiver
        );

        /////////////////////
        // Register facets //
        /////////////////////

        // PoolBase
        poolBaseSelectors.push(poolBaseImpl.accountsByToken.selector);
        poolBaseSelectors.push(poolBaseImpl.balanceOf.selector);
        poolBaseSelectors.push(poolBaseImpl.balanceOfBatch.selector);
        poolBaseSelectors.push(poolBaseImpl.isApprovedForAll.selector);
        poolBaseSelectors.push(poolBaseImpl.name.selector);
        poolBaseSelectors.push(poolBaseImpl.safeBatchTransferFrom.selector);
        poolBaseSelectors.push(poolBaseImpl.safeTransferFrom.selector);
        poolBaseSelectors.push(poolBaseImpl.setApprovalForAll.selector);
        poolBaseSelectors.push(poolBaseImpl.tokensByAccount.selector);
        poolBaseSelectors.push(poolBaseImpl.totalHolders.selector);
        poolBaseSelectors.push(poolBaseImpl.totalSupply.selector);

        // PoolCoreMock
        poolCoreMockSelectors.push(poolCoreMockImpl._getPricing.selector);
        poolCoreMockSelectors.push(
            poolCoreMockImpl.exposed_getStrandedArea.selector
        );
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_cross.selector);
        poolCoreMockSelectors.push(
            poolCoreMockImpl.exposed_getStrandedMarketPriceUpdate.selector
        );
        poolCoreMockSelectors.push(
            poolCoreMockImpl.exposed_isMarketPriceStranded.selector
        );
        poolCoreMockSelectors.push(poolCoreMockImpl.getCurrentTick.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getLiquidityRate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.formatTokenId.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.quoteRFQHash.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.parseTokenId.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.protocolFees.selector);

        // PoolCore
        poolCoreSelectors.push(poolCoreImpl.annihilate.selector);
        poolCoreSelectors.push(poolCoreImpl.claim.selector);
        poolCoreSelectors.push(poolCoreImpl.exercise.selector);
        poolCoreSelectors.push(poolCoreImpl.getClaimableFees.selector);
        poolCoreSelectors.push(poolCoreImpl.getNearestTicksBelow.selector);
        poolCoreSelectors.push(poolCoreImpl.getPoolSettings.selector);
        poolCoreSelectors.push(poolCoreImpl.marketPrice.selector);
        poolCoreSelectors.push(poolCoreImpl.settle.selector);
        poolCoreSelectors.push(poolCoreImpl.settlePosition.selector);
        poolCoreSelectors.push(poolCoreImpl.takerFee.selector);
        poolCoreSelectors.push(poolCoreImpl.transferPosition.selector);
        poolCoreSelectors.push(poolCoreImpl.writeFrom.selector);

        // PoolDepositWithdraw
        poolDepositWithdrawSelectors.push(
            bytes4(
                keccak256(
                    "deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256,(address,uint256,uint256,uint256,bytes))"
                )
            )
        );
        poolDepositWithdrawSelectors.push(
            bytes4(
                keccak256(
                    "deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256,(address,uint256,uint256,uint256,bytes),bool)"
                )
            )
        );
        poolDepositWithdrawSelectors.push(
            poolDepositWithdrawImpl.withdraw.selector
        );

        // PoolTrade
        poolTradeSelectors.push(poolTradeImpl.cancelQuotesRFQ.selector);
        poolTradeSelectors.push(poolTradeImpl.fillQuoteRFQ.selector);
        poolTradeSelectors.push(poolTradeImpl.flashLoan.selector);
        poolTradeSelectors.push(poolTradeImpl.getQuoteAMM.selector);
        poolTradeSelectors.push(poolTradeImpl.getQuoteRFQFilledAmount.selector);
        poolTradeSelectors.push(poolTradeImpl.isQuoteRFQValid.selector);
        poolTradeSelectors.push(poolTradeImpl.trade.selector);

        IDiamondWritableInternal.FacetCut[]
            memory facetCuts = new IDiamondWritableInternal.FacetCut[](5);

        facetCuts[0] = IDiamondWritableInternal.FacetCut(
            address(poolBaseImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolBaseSelectors
        );

        facetCuts[1] = IDiamondWritableInternal.FacetCut(
            address(poolCoreMockImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolCoreMockSelectors
        );

        facetCuts[2] = IDiamondWritableInternal.FacetCut(
            address(poolCoreImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolCoreSelectors
        );

        facetCuts[3] = IDiamondWritableInternal.FacetCut(
            address(poolDepositWithdrawImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolDepositWithdrawSelectors
        );

        facetCuts[4] = IDiamondWritableInternal.FacetCut(
            address(poolTradeImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolTradeSelectors
        );

        diamond.diamondCut(facetCuts, address(0), "");

        ///////////////////////

        posKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: UD60x18.wrap(0.1 ether),
            upper: UD60x18.wrap(0.3 ether),
            orderType: Position.OrderType.LC
        });
    }

    function deposit(
        uint256 depositSize
    ) internal returns (uint256 initialCollateral) {
        return deposit(UD60x18.wrap(depositSize));
    }

    function deposit(
        UD60x18 depositSize
    ) internal returns (uint256 initialCollateral) {
        return deposit(pool, poolKey.strike, depositSize);
    }

    function deposit(
        IPoolMock _pool,
        UD60x18 strike,
        UD60x18 depositSize
    ) internal returns (uint256 initialCollateral) {
        bool isCall = poolKey.isCallPool;

        IERC20 token = IERC20(getPoolToken(isCall));
        initialCollateral = scaleDecimals(
            isCall ? depositSize : depositSize * strike,
            isCall
        );

        vm.startPrank(users.lp);

        deal(address(token), users.lp, initialCollateral);
        token.approve(address(router), initialCollateral);

        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = _pool
            .getNearestTicksBelow(posKey.lower, posKey.upper);

        _pool.deposit(
            posKey,
            nearestBelowLower,
            nearestBelowUpper,
            depositSize,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        vm.stopPrank();
    }

    function getPoolToken(bool isCall) internal view returns (address) {
        return isCall ? base : quote;
    }

    function contractsToCollateral(
        UD60x18 amount,
        bool isCall
    ) internal view returns (UD60x18) {
        return isCall ? amount : amount * poolKey.strike;
    }

    function scaleDecimals(
        UD60x18 amount,
        bool isCall
    ) internal view returns (uint256) {
        uint8 decimals = ISolidStateERC20(getPoolToken(isCall)).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
    }

    function scaleDecimals(
        uint256 amount,
        bool isCall
    ) internal view returns (UD60x18) {
        uint8 decimals = ISolidStateERC20(getPoolToken(isCall)).decimals();
        return UD60x18.wrap(OptionMath.scaleDecimals(amount, decimals, 18));
    }

    function tokenId() internal view returns (uint256) {
        return
            PoolStorage.formatTokenId(
                posKey.operator,
                posKey.lower,
                posKey.upper,
                posKey.orderType
            );
    }
}
