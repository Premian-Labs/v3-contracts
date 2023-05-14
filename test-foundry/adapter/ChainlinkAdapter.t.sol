// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {Test} from "forge-std/Test.sol";

import "../Addresses.sol";
import {Assertions} from "../Assertions.sol";
import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IChainlinkAdapter} from "contracts/adapter/chainlink/IChainlinkAdapter.sol";
import {ChainlinkAdapter} from "contracts/adapter/chainlink/ChainlinkAdapter.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {ChainlinkOraclePriceStub} from "contracts/test/adapter/ChainlinkOraclePriceStub.sol";

contract ChainlinkAdapterTest is Test, Assertions {
    struct Path {
        IChainlinkAdapter.PricingPath path;
        address tokenIn;
        address tokenOut;
    }

    uint256 mainnetFork;

    Path[][] paths;
    ChainlinkAdapter adapter;
    uint256 target;

    function setUp() public {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );
        mainnetFork = vm.createFork(ETH_RPC_URL, 17100000);
        vm.selectFork(mainnetFork);

        target = 1676016000;
        for (uint256 i = 0; i < 8; i++) {
            paths.push();
        }

        // prettier-ignore
        {
            // ETH_USD
            paths[0].push(Path(IChainlinkAdapter.PricingPath.ETH_USD, WETH, CHAINLINK_USD));  // IN is ETH, OUT is USD
            paths[0].push(Path(IChainlinkAdapter.PricingPath.ETH_USD, CHAINLINK_USD, WETH)); // IN is USD, OUT is ETH
            paths[0].push(Path(IChainlinkAdapter.PricingPath.ETH_USD, CHAINLINK_ETH, CHAINLINK_USD)); // IN is ETH, OUT is USD

            // TOKEN_USD
            paths[1].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD, DAI, CHAINLINK_USD)); // IN (tokenA) => OUT (tokenB) is USD
            paths[1].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD, AAVE, CHAINLINK_USD)); // IN (tokenA) => OUT (tokenB) is USD
            // Note: Assumes WBTC/USD feed exists
            paths[1].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD, CHAINLINK_USD, WBTC)); // IN (tokenB) is USD => OUT (tokenA)
            paths[1].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD, WBTC, CHAINLINK_USD)); // IN (tokenA) => OUT (tokenB) is USD

            // TOKEN_ETH
            paths[2].push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH, BNT, WETH)); // IN (tokenA) => OUT (tokenB) is ETH
            paths[2].push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH, AXS, WETH)); // IN (tokenB) => OUT (tokenA) is ETH
            paths[2].push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH, WETH, CRV)); // IN (tokenA) is ETH => OUT (tokenB)

            // TOKEN_USD_TOKEN
            paths[3].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, CRV, AAVE)); // IN (tokenB) => USD => OUT (tokenA)
            paths[3].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, DAI, AAVE)); // IN (tokenA) => USD => OUT (tokenB)
            paths[3].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, AAVE, DAI)); // IN (tokenB) => USD => OUT (tokenA)
            paths[3].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, CRV, USDC)); // IN (tokenB) => USD => OUT (tokenA)
            paths[3].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, USDC, COMP)); // IN (tokenA) => USD => OUT (tokenB)
            // Note: Assumes WBTC/USD feed exists
            paths[3].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, DAI, WBTC)); // IN (tokenB) => USD => OUT (tokenA)
            paths[3].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, WBTC, USDC)); // IN (tokenA) => USD => OUT (tokenB)

            // TOKEN_ETH_TOKEN
            paths[4].push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH_TOKEN, BOND, AXS)); // IN (tokenA) => ETH => OUT (tokenB)
            paths[4].push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH_TOKEN, ALPHA, BOND)); // IN (tokenB) => ETH => OUT (tokenA)

            // A_USD_ETH_B
            paths[5].push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, FXS, WETH)); // IN (tokenA) => USD, OUT (tokenB) is ETH
            paths[5].push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, WETH, MATIC)); // IN (tokenB) is ETH, USD => OUT (tokenA)
            paths[5].push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, USDC, AXS)); // IN (tokenA) is USD, ETH => OUT (tokenB)
            paths[5].push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, ALPHA, DAI)); // IN (tokenB) => ETH, OUT is USD (tokenA)
            paths[5].push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, DAI, ALPHA));
            paths[5].push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, FXS, AXS)); // IN (tokenA) => USD, ETH => OUT (tokenB)
            paths[5].push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, ALPHA, MATIC)); // IN (tokenB) => ETH, USD => OUT (tokenA)
            // Note: Assumes WBTC/USD feed exists
            paths[5].push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, WETH, WBTC)); // IN (tokenB) => ETH, USD => OUT (tokenA)

            // A_ETH_USD_B
            // We can't test the following two cases, because we would need a token that is
            // supported by chainlink and lower than USD (address(840))
            // - IN (tokenA) => ETH, OUT (tokenB) is USD
            // - IN (tokenB) is USD, ETH => OUT (tokenA)
            paths[6].push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, WETH, IMX)); // IN (tokenA) is ETH, USD => OUT (tokenB)
            paths[6].push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, IMX, WETH)); // IN (tokenB) => USD, OUT is ETH (tokenA)
            paths[6].push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, AXS, IMX)); // IN (tokenA) => ETH, USD => OUT (tokenB)
            paths[6].push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, FXS, BOND)); // IN (tokenB) => ETH, USD => OUT (tokenA)
            paths[6].push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, BOND, FXS)); // IN (tokenA) => USD, ETH => OUT (tokenB)

            // TOKEN_USD_BTC_WBTC
            // Note: Assumes WBTC/USD feed does not exist
            paths[7].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, CHAINLINK_USD)); // IN (tokenA) => BTC, OUT is USD
            paths[7].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, CHAINLINK_BTC)); // IN (tokenA) => BTC, OUT is BTC
            paths[7].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, WETH)); // IN (tokenA) => BTC, OUT is ETH (tokenB)
            paths[7].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WETH, WBTC)); // IN (tokenB) is ETH, BTC => OUT (tokenA)
            paths[7].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, DAI, WBTC)); // IN (tokenB) => USD, BTC => OUT (tokenA)
            paths[7].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, USDC)); // IN (tokenA) => BTC, USD => OUT (tokenB)
            paths[7].push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, BNT)); // IN (tokenA) => USD,  BTC => OUT (tokenB)
        }

        address implementation = address(new ChainlinkAdapter(WETH, WBTC));
        address proxy = address(new ProxyUpgradeableOwnable(implementation));
        adapter = ChainlinkAdapter(proxy);

        adapter.batchRegisterFeedMappings(feeds());
    }

    function _deployStub()
        internal
        returns (ChainlinkOraclePriceStub stub, address stubCoin)
    {
        stub = new ChainlinkOraclePriceStub();
        stubCoin = address(100);

        IFeedRegistry.FeedMappingArgs[]
            memory data = new IFeedRegistry.FeedMappingArgs[](1);

        data[0] = IFeedRegistry.FeedMappingArgs(
            stubCoin,
            CHAINLINK_USD,
            address(stub)
        );

        adapter.batchRegisterFeedMappings(data);
        adapter.upsertPair(stubCoin, CHAINLINK_USD);

        return (stub, stubCoin);
    }

    function test_isPairSupported_ReturnFalse_IfPairNotSupported() public {
        (bool isCached, ) = adapter.isPairSupported(WETH, DAI);
        assertFalse(isCached);
    }

    function test_isPairSupported_ReturnFalse_IfPathDoesNotExist() public {
        (, bool hasPath) = adapter.isPairSupported(WETH, WBTC);
        assertTrue(hasPath);
    }

    function test_upserPair_ShouldNotRevert_IfCalledMultipleTime_ForSamePair()
        public
    {
        adapter.upsertPair(WETH, DAI);
        (bool isCached, ) = adapter.isPairSupported(WETH, DAI);
        assertTrue(isCached);

        adapter.upsertPair(WETH, DAI);
    }

    function test_upsertPair_RevertIf_PairCannotBeSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                address(0),
                WETH
            )
        );
        adapter.upsertPair(address(0), WETH);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                WBTC,
                address(0)
            )
        );
        adapter.upsertPair(WBTC, address(0));
    }

    // ToDo : See why this doesnt compile
    //    function test_upsertPair_EmitUpdatePathForPair_WhenPathIsUpdated() public {
    //        vm.expectEmit(false, false, false, true);
    //        emit ChainlinkAdapter.UpdatedPathForPair(
    //            WETH,
    //            DAI,
    //            IChainlinkAdapter.PricingPath.ETH_TOKEN
    //        );
    //        adapter.upsertPair(WETH, DAI);
    //    }

    function test_batchRegisterFeedMappings_RevertIf_TokenEqualDenomination()
        public
    {
        IFeedRegistry.FeedMappingArgs[]
            memory data = new IFeedRegistry.FeedMappingArgs[](1);
        data[0] = IFeedRegistry.FeedMappingArgs(EUL, EUL, address(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IFeedRegistry.FeedRegistry__TokensAreSame.selector,
                EUL,
                EUL
            )
        );
        adapter.batchRegisterFeedMappings(data);
    }

    function test_batchRegisterFeedMappings_RevertIf_TokenOrDenominationIsZero()
        public
    {
        IFeedRegistry.FeedMappingArgs[]
            memory data = new IFeedRegistry.FeedMappingArgs[](1);

        data[0] = IFeedRegistry.FeedMappingArgs(address(0), DAI, address(1));
        vm.expectRevert(IFeedRegistry.FeedRegistry__ZeroAddress.selector);
        adapter.batchRegisterFeedMappings(data);

        data[0] = IFeedRegistry.FeedMappingArgs(EUL, address(0), address(1));
        vm.expectRevert(IFeedRegistry.FeedRegistry__ZeroAddress.selector);
        adapter.batchRegisterFeedMappings(data);
    }

    function test_feed_ReturnFeed() public {
        IFeedRegistry.FeedMappingArgs[] memory _feeds = feeds();

        for (uint256 i = 0; i < _feeds.length; i++) {
            assertEq(
                adapter.feed(_feeds[i].token, _feeds[i].denomination),
                _feeds[i].feed
            );
        }
    }

    function test_feed_ReturnZeroAddress_IfFeedDoesNotExist() public {
        assertEq(adapter.feed(EUL, DAI), address(0));
    }

    function test_quote_ReturnQuoteUsingCorrectDenomination() public {
        address tokenIn = WETH;
        address tokenOut = DAI;

        adapter.upsertPair(tokenIn, tokenOut);

        UD60x18 quote = adapter.quote(tokenIn, tokenOut);
        UD60x18 invertedQuote = adapter.quote(tokenOut, tokenIn);

        assertEq(quote, ud(1e18) / invertedQuote);

        //

        tokenIn = CRV;
        tokenOut = AAVE;

        adapter.upsertPair(tokenIn, tokenOut);

        quote = adapter.quote(tokenIn, tokenOut);
        invertedQuote = adapter.quote(tokenOut, tokenIn);

        assertEq(quote, ud(1e18) / invertedQuote);
    }

    function test_quote_ReturnCorrectQuote_IfPathExistsButNotCached() public {
        UD60x18 quoteBeforeUpsert = adapter.quote(WETH, DAI);

        adapter.upsertPair(WETH, DAI);
        UD60x18 quote = adapter.quote(WETH, DAI);

        assertEq(quote, quoteBeforeUpsert);
    }

    function test_quote_RevertIf_PairNotSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairNotSupported.selector,
                WETH,
                address(0)
            )
        );
        adapter.quote(WETH, address(0));
    }

    function test_quote_CatchRevert() public {
        (ChainlinkOraclePriceStub stub, address stubCoin) = _deployStub();

        int256[] memory prices = new int256[](1);
        uint256[] memory timestamps = new uint256[](1);

        prices[0] = 100000000000;
        timestamps[0] = target - 90000;

        stub.setup(
            ChainlinkOraclePriceStub
                .FailureMode
                .LAST_ROUND_DATA_REVERT_WITH_REASON,
            prices,
            timestamps
        );

        vm.expectRevert("reverted with reason");
        adapter.quote(stubCoin, CHAINLINK_USD);

        //

        stub.setup(
            ChainlinkOraclePriceStub.FailureMode.LAST_ROUND_DATA_REVERT,
            prices,
            timestamps
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainlinkAdapter
                    .ChainlinkAdapter__LatestRoundDataCallReverted
                    .selector,
                ""
            )
        );
        adapter.quote(stubCoin, CHAINLINK_USD);
    }
}
