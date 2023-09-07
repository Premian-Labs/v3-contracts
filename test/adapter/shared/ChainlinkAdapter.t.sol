// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {ChainlinkAdapter} from "contracts/adapter/chainlink/ChainlinkAdapter.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {ChainlinkOraclePriceStub} from "contracts/test/adapter/ChainlinkOraclePriceStub.sol";

import {Base_Test} from "../../Base.t.sol";

abstract contract ChainlinkAdapter_Shared_Test is Base_Test {
    // Constants
    address constant CHAINLINK_BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    address constant CHAINLINK_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant CHAINLINK_USD = 0x0000000000000000000000000000000000000348;
    address constant GNO = 0x6810e776880C02933D47DB1b9fc05908e5386b96;
    address constant BIT = 0x1A4b46696b2bB4794Eb3D4c26f1c55F9170fa4C5;
    address constant BNT = 0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C;
    address constant EUL = 0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b;
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant AMP = 0xfF20817765cB7f73d4bde2e66e067E58D11095C2;
    address constant IMX = 0xF57e7e7C23978C3cAEC3C3548E3D615c346e79fF;
    address constant ENS = 0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72;
    address constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address constant AXS = 0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address constant BOND = 0x0391D2021f89DC339F60Fff84546EA23E337750f;
    address constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant LOOKS = 0xf4d2888d29D722226FafA5d9B24F9164c092421E;
    address constant MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address constant ALPHA = 0xa1faa113cbE53436Df28FF0aEe54275c13B40975;

    // Test contracts
    ChainlinkAdapter internal adapter;
    ChainlinkOraclePriceStub internal stub;

    // Variables
    uint256 internal target;
    address internal stubCoin;

    function setUp() public virtual override {
        Base_Test.setUp();

        target = 1676016000;
    }

    function getStartTimestamp() internal virtual override returns (uint256) {
        return block.timestamp;
    }

    function getStartBlock() internal virtual override returns (uint256) {
        return 16_597_500;
    }

    /// @dev Deploys the Chainlink adapter.
    function deploy() internal virtual override {
        address implementation = address(new ChainlinkAdapter(WETH, WBTC));
        address proxy = address(new ProxyUpgradeableOwnable(implementation));
        adapter = ChainlinkAdapter(proxy);

        adapter.batchRegisterFeedMappings(feeds());

        // Deploy stub
        stub = new ChainlinkOraclePriceStub();
        stubCoin = address(100);

        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](2);
        data[0] = IFeedRegistry.FeedMappingArgs(stubCoin, CHAINLINK_USD, address(stub));
        data[1] = IFeedRegistry.FeedMappingArgs(stubCoin, CHAINLINK_ETH, address(stub));

        adapter.batchRegisterFeedMappings(data);
        adapter.upsertPair(stubCoin, CHAINLINK_USD);
        adapter.upsertPair(stubCoin, CHAINLINK_ETH);

        address[] memory relayers = new address[](1);
        relayers[0] = users.relayer;

        adapter.addWhitelistedRelayers(relayers);

        vm.label({account: address(adapter), newLabel: "ChainlinkAdapter"});
    }

    // prettier-ignore
    function feeds() pure internal returns (IFeedRegistry.FeedMappingArgs[] memory r) {
        r = new IFeedRegistry.FeedMappingArgs[](26);

        r[0]  = IFeedRegistry.FeedMappingArgs( CHAINLINK_ETH, CHAINLINK_USD,  0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 );
        r[1]  = IFeedRegistry.FeedMappingArgs( CHAINLINK_BTC, CHAINLINK_USD,  0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c );
        r[2]  = IFeedRegistry.FeedMappingArgs( YFI,           CHAINLINK_USD,  0xA027702dbb89fbd58938e4324ac03B58d812b0E1 );
        r[3]  = IFeedRegistry.FeedMappingArgs( ENS,           CHAINLINK_USD,  0x5C00128d4d1c2F4f652C267d7bcdD7aC99C16E16 );
        r[4]  = IFeedRegistry.FeedMappingArgs( USDC,          CHAINLINK_USD,  0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6 );
        r[5]  = IFeedRegistry.FeedMappingArgs( DAI,           CHAINLINK_USD,  0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9 );
        r[6]  = IFeedRegistry.FeedMappingArgs( BNT,           CHAINLINK_USD,  0x1E6cF0D433de4FE882A437ABC654F58E1e78548c );
        r[7]  = IFeedRegistry.FeedMappingArgs( CRV,           CHAINLINK_USD,  0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f );
        r[8]  = IFeedRegistry.FeedMappingArgs( AMP,           CHAINLINK_USD,  0xfAaA7460eD59C12E204349766CE73Cf5202e6aD6 );
        r[9]  = IFeedRegistry.FeedMappingArgs( IMX,           CHAINLINK_USD,  0xBAEbEFc1D023c0feCcc047Bff42E75F15Ff213E6 );
        r[10] = IFeedRegistry.FeedMappingArgs( FXS,           CHAINLINK_USD,  0x6Ebc52C8C1089be9eB3945C4350B68B8E4C2233f );
        r[11] = IFeedRegistry.FeedMappingArgs( AAVE,          CHAINLINK_USD,  0x547a514d5e3769680Ce22B2361c10Ea13619e8a9 );
        r[12] = IFeedRegistry.FeedMappingArgs( COMP,          CHAINLINK_USD,  0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5 );
        r[13] = IFeedRegistry.FeedMappingArgs( MATIC,         CHAINLINK_USD,  0x7bAC85A8a13A4BcD8abb3eB7d6b4d632c5a57676 );
        r[14] = IFeedRegistry.FeedMappingArgs( LINK,          CHAINLINK_ETH,  0xDC530D9457755926550b59e8ECcdaE7624181557 );
        r[15] = IFeedRegistry.FeedMappingArgs( UNI,           CHAINLINK_ETH,  0xD6aA3D25116d8dA79Ea0246c4826EB951872e02e );
        r[16] = IFeedRegistry.FeedMappingArgs( USDT,          CHAINLINK_ETH,  0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46 );
        r[17] = IFeedRegistry.FeedMappingArgs( AXS,           CHAINLINK_ETH,  0x8B4fC5b68cD50eAc1dD33f695901624a4a1A0A8b );
        r[18] = IFeedRegistry.FeedMappingArgs( BOND,          CHAINLINK_ETH,  0xdd22A54e05410D8d1007c38b5c7A3eD74b855281 );
        r[19] = IFeedRegistry.FeedMappingArgs( ALPHA,         CHAINLINK_ETH,  0x89c7926c7c15fD5BFDB1edcFf7E7fC8283B578F6 );
        r[20] = IFeedRegistry.FeedMappingArgs( BNT,           CHAINLINK_ETH,  0xCf61d1841B178fe82C8895fe60c2EDDa08314416 );
        r[21] = IFeedRegistry.FeedMappingArgs( CRV,           CHAINLINK_ETH,  0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e );
        r[22] = IFeedRegistry.FeedMappingArgs( AAVE,          CHAINLINK_ETH,  0x6Df09E975c830ECae5bd4eD9d90f3A95a4f88012 );
        r[23] = IFeedRegistry.FeedMappingArgs( COMP,          CHAINLINK_ETH,  0x1B39Ee86Ec5979ba5C322b826B3ECb8C79991699 );
        r[24] = IFeedRegistry.FeedMappingArgs( DAI,           CHAINLINK_ETH,  0x773616E4d11A78F511299002da57A0a94577F1f4 );
        r[25] = IFeedRegistry.FeedMappingArgs( WBTC,          CHAINLINK_BTC,  0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23 );
    }
}
