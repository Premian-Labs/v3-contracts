export type Token = { address: string; decimals: number; symbol: string };

export const CHAINLINK_BTC = '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB';
export const CHAINLINK_ETH = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
export const CHAINLINK_USD = '0x0000000000000000000000000000000000000348';

// NOTE: Ethereum Addresses Only
// prettier-ignore
export const tokens: { [symbol: string]: Token } =  {
    'BNT': { address: '0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C', decimals: 18, symbol: 'BNT' },
    'CRV': { address: '0xD533a949740bb3306d119CC777fa900bA034cd52', decimals: 18, symbol: 'CRV' },
    'AMP': { address: '0xfF20817765cB7f73d4bde2e66e067E58D11095C2', decimals: 18, symbol: 'AMP' },
    'IMX': { address: '0xf57e7e7c23978c3caec3c3548e3d615c346e79ff', decimals: 18, symbol: 'IMX' },
    'FXS': { address: '0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0', decimals: 18, symbol: 'FXS' },
    'AXS': { address: '0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b', decimals: 18, symbol: 'AXS' },
    'DAI': { address: '0x6B175474E89094C44Da98b954EedeAC495271d0F', decimals: 18, symbol: 'DAI' },
    'USDC': { address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', decimals: 6, symbol: 'USDC' },
    'USDT': { address: '0xdAC17F958D2ee523a2206206994597C13D831ec7', decimals: 6, symbol: 'USDT' },
    'WBTC': { address: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', decimals: 8, symbol: 'WBTC' },
    'WETH': { address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', decimals: 18, symbol: 'WETH' },
    'AAVE': { address: '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9', decimals: 18, symbol: 'AAVE' },
    'COMP': { address: '0xc00e94Cb662C3520282E6f5717214004A7f26888', decimals: 18, symbol: 'COMP' },
    'BOND': { address: '0x0391D2021f89DC339F60Fff84546EA23E337750f', decimals: 18, symbol: 'BOND' },
    'MATIC': { address: '0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0', decimals: 18, symbol: 'MATIC' },
    'ALPHA': { address: '0xa1faa113cbE53436Df28FF0aEe54275c13B40975', decimals: 18, symbol: 'ALPHA' },
}

// NOTE: Ethereum Addresses Only
// prettier-ignore
export const feeds = [
    { token: CHAINLINK_ETH, denomination: CHAINLINK_USD, feed: '0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419'},
    { token: CHAINLINK_BTC, denomination: CHAINLINK_USD, feed: '0xf4030086522a5beea4988f8ca5b36dbc97bee88c'},
    { token: CHAINLINK_BTC, denomination: CHAINLINK_ETH, feed: '0xdeb288f737066589598e9214e782fa5a8ed689e8'},
    { token: tokens.BNT.address, denomination: CHAINLINK_USD, feed: '0x1e6cf0d433de4fe882a437abc654f58e1e78548c'},
    { token: tokens.CRV.address, denomination: CHAINLINK_USD, feed: '0xcd627aa160a6fa45eb793d19ef54f5062f20f33f'},
    { token: tokens.AMP.address, denomination: CHAINLINK_USD, feed: '0xfaaa7460ed59c12e204349766ce73cf5202e6ad6'},
    { token: tokens.IMX.address, denomination: CHAINLINK_USD, feed: '0xbaebefc1d023c0feccc047bff42e75f15ff213e6'},
    { token: tokens.FXS.address, denomination: CHAINLINK_USD, feed: '0x6ebc52c8c1089be9eb3945c4350b68b8e4c2233f'},
    { token: tokens.DAI.address, denomination: CHAINLINK_USD, feed: '0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9'},
    { token: tokens.USDC.address, denomination: CHAINLINK_USD, feed: '0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6'},
    { token: tokens.USDT.address, denomination: CHAINLINK_USD, feed: '0x3E7d1eAB13ad0104d2750B8863b489D65364e32D'},
    { token: tokens.AAVE.address, denomination: CHAINLINK_USD, feed: '0x547a514d5e3769680Ce22B2361c10Ea13619e8a9'},
    { token: tokens.COMP.address, denomination: CHAINLINK_USD, feed: '0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5'},
    { token: tokens.MATIC.address, denomination: CHAINLINK_USD, feed: '0x7bAC85A8a13A4BcD8abb3eB7d6b4d632c5a57676'},
    { token: tokens.AXS.address, denomination: CHAINLINK_ETH, feed: '0x8B4fC5b68cD50eAc1dD33f695901624a4a1A0A8b'},
    { token: tokens.BOND.address, denomination: CHAINLINK_ETH, feed: '0xdd22A54e05410D8d1007c38b5c7A3eD74b855281'},
    { token: tokens.ALPHA.address, denomination: CHAINLINK_ETH, feed: '0x89c7926c7c15fD5BFDB1edcFf7E7fC8283B578F6'},
    { token: tokens.BNT.address, denomination: CHAINLINK_ETH, feed: '0xCf61d1841B178fe82C8895fe60c2EDDa08314416'},
    { token: tokens.CRV.address, denomination: CHAINLINK_ETH, feed: '0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e'},
    { token: tokens.DAI.address, denomination: CHAINLINK_ETH, feed: '0x773616E4d11A78F511299002da57A0a94577F1f4'},
    { token: tokens.USDC.address, denomination: CHAINLINK_ETH, feed: '0x986b5E1e1755e3C2440e960477f25201B0a8bbD4'},
    { token: tokens.USDT.address, denomination: CHAINLINK_ETH, feed: '0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46'},
    { token: tokens.AAVE.address, denomination: CHAINLINK_ETH, feed: '0x6Df09E975c830ECae5bd4eD9d90f3A95a4f88012'},
    { token: tokens.COMP.address, denomination: CHAINLINK_ETH, feed: '0x1B39Ee86Ec5979ba5C322b826B3ECb8C79991699'},
]
