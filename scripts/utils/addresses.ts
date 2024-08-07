import arbitrum from '../../deployments/arbitrum/metadata.json';
import arbitrumGoerli from '../../deployments/arbitrumGoerli/metadata.json';

export type Token = { address: string; decimals: number; symbol: string };

export const CHAINLINK_BTC = '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB';
export const CHAINLINK_ETH = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
export const CHAINLINK_USD = '0x0000000000000000000000000000000000000348';

// NOTE: Ethereum Addresses Only
// prettier-ignore
export const tokens: { [symbol: string]: Token } =  {
    'CHAINLINK_BTC': { address: '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB', decimals: 8, symbol: 'CHAINLINK_BTC' },
    'CHAINLINK_ETH': { address: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', decimals: 18, symbol: 'CHAINLINK_ETH' },
    'CHAINLINK_USD': { address: '0x0000000000000000000000000000000000000348', decimals: 8, symbol: 'CHAINLINK_USD' },
    'GNO': { address: '0x6810e776880C02933D47DB1b9fc05908e5386b96', decimals: 18, symbol: 'GNO' },
    'BIT': { address: '0x1A4b46696b2bB4794Eb3D4c26f1c55F9170fa4C5', decimals: 18, symbol: 'BIT' },
    'BNT': { address: '0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C', decimals: 18, symbol: 'BNT' },
    'EUL': { address: '0xd9fcd98c322942075a5c3860693e9f4f03aae07b', decimals: 18, symbol: 'EUL' },
    'CRV': { address: '0xD533a949740bb3306d119CC777fa900bA034cd52', decimals: 18, symbol: 'CRV' },
    'AMP': { address: '0xfF20817765cB7f73d4bde2e66e067E58D11095C2', decimals: 18, symbol: 'AMP' },
    'IMX': { address: '0xf57e7e7c23978c3caec3c3548e3d615c346e79ff', decimals: 18, symbol: 'IMX' },
    'ENS': { address: '0xc18360217d8f7ab5e7c516566761ea12ce7f9d72', decimals: 18, symbol: 'ENS' },
    'FXS': { address: '0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0', decimals: 18, symbol: 'FXS' },
    'AXS': { address: '0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b', decimals: 18, symbol: 'AXS' },
    'DAI': { address: '0x6B175474E89094C44Da98b954EedeAC495271d0F', decimals: 18, symbol: 'DAI' },
    'MKR': { address: '0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2', decimals: 18, symbol: 'MKR' },
    'UNI': { address: '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984', decimals: 18, symbol: 'UNI' },
    'YFI': { address: '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e', decimals: 18, symbol: 'YFI' },
    'USDC': { address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', decimals: 6, symbol: 'USDC' },
    'USDT': { address: '0xdAC17F958D2ee523a2206206994597C13D831ec7', decimals: 6, symbol: 'USDT' },
    'WBTC': { address: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', decimals: 8, symbol: 'WBTC' },
    'WETH': { address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', decimals: 18, symbol: 'WETH' },
    'AAVE': { address: '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9', decimals: 18, symbol: 'AAVE' },
    'COMP': { address: '0xc00e94Cb662C3520282E6f5717214004A7f26888', decimals: 18, symbol: 'COMP' },
    'BOND': { address: '0x0391D2021f89DC339F60Fff84546EA23E337750f', decimals: 18, symbol: 'BOND' },
    'FRAX': { address: '0x853d955aCEf822Db058eb8505911ED77F175b99e', decimals: 18, symbol: 'FRAX' },
    'LINK': { address: '0x514910771AF9Ca656af840dff83E8264EcF986CA', decimals: 18, symbol: 'LINK' },
    'LOOKS': { address: '0xf4d2888d29D722226FafA5d9B24F9164c092421E', decimals: 18, symbol: 'LOOKS' },
    'MATIC': { address: '0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0', decimals: 18, symbol: 'MATIC' },
    'ALPHA': { address: '0xa1faa113cbE53436Df28FF0aEe54275c13B40975', decimals: 18, symbol: 'ALPHA' },
}

// NOTE: Ethereum Addresses Only
// prettier-ignore
export const feeds = [
    { token: tokens.CHAINLINK_BTC.address, denomination: tokens.CHAINLINK_USD.address, feed: '0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c'},
    { token: tokens.YFI.address, denomination: tokens.CHAINLINK_USD.address, feed: '0xA027702dbb89fbd58938e4324ac03B58d812b0E1'},
    { token: tokens.ENS.address, denomination: tokens.CHAINLINK_USD.address, feed: '0x5C00128d4d1c2F4f652C267d7bcdD7aC99C16E16'},
    { token: tokens.USDC.address, denomination: tokens.CHAINLINK_USD.address, feed: '0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6'},
    { token: tokens.WETH.address, denomination: tokens.CHAINLINK_USD.address, feed: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419'},
    { token: tokens.DAI.address, denomination: tokens.CHAINLINK_USD.address, feed: '0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9'},
    { token: tokens.BNT.address, denomination: tokens.CHAINLINK_USD.address, feed: '0x1E6cF0D433de4FE882A437ABC654F58E1e78548c'},
    { token: tokens.CRV.address, denomination: tokens.CHAINLINK_USD.address, feed: '0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f'},
    { token: tokens.AMP.address, denomination: tokens.CHAINLINK_USD.address, feed: '0xfAaA7460eD59C12E204349766CE73Cf5202e6aD6'},
    { token: tokens.IMX.address, denomination: tokens.CHAINLINK_USD.address, feed: '0xBAEbEFc1D023c0feCcc047Bff42E75F15Ff213E6'},
    { token: tokens.FXS.address, denomination: tokens.CHAINLINK_USD.address, feed: '0x6Ebc52C8C1089be9eB3945C4350B68B8E4C2233f'},
    { token: tokens.AAVE.address, denomination: tokens.CHAINLINK_USD.address, feed: '0x547a514d5e3769680Ce22B2361c10Ea13619e8a9'},
    { token: tokens.COMP.address, denomination: tokens.CHAINLINK_USD.address, feed: '0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5'},
    { token: tokens.MATIC.address, denomination: tokens.CHAINLINK_USD.address, feed: '0x7bAC85A8a13A4BcD8abb3eB7d6b4d632c5a57676'},
    { token: tokens.LINK.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0xDC530D9457755926550b59e8ECcdaE7624181557'},
    { token: tokens.UNI.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0xD6aA3D25116d8dA79Ea0246c4826EB951872e02e'},
    { token: tokens.USDT.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46'},
    { token: tokens.AXS.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0x8B4fC5b68cD50eAc1dD33f695901624a4a1A0A8b'},
    { token: tokens.BOND.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0xdd22A54e05410D8d1007c38b5c7A3eD74b855281'},
    { token: tokens.ALPHA.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0x89c7926c7c15fD5BFDB1edcFf7E7fC8283B578F6'},
    { token: tokens.BNT.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0xCf61d1841B178fe82C8895fe60c2EDDa08314416'},
    { token: tokens.CRV.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e'},
    { token: tokens.AAVE.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0x6Df09E975c830ECae5bd4eD9d90f3A95a4f88012'},
    { token: tokens.COMP.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0x1B39Ee86Ec5979ba5C322b826B3ECb8C79991699'},
    { token: tokens.DAI.address, denomination: tokens.CHAINLINK_ETH.address, feed: '0x773616E4d11A78F511299002da57A0a94577F1f4'},
    { token: tokens.WBTC.address, denomination: tokens.CHAINLINK_BTC.address, feed: '0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23'},
]

export const arbitrumFeeds = [
  {
    token: CHAINLINK_ETH,
    denomination: CHAINLINK_USD,
    feed: '0x639fe6ab55c921f74e7fac1ee960c0b6293ba612',
  },
  {
    token: arbitrum.tokens.WBTC,
    denomination: CHAINLINK_USD,
    feed: '0xd0C7101eACbB49F3deCcCc166d238410D6D46d57',
  },
  {
    token: arbitrum.tokens.ARB,
    denomination: CHAINLINK_USD,
    feed: '0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6',
  },
  {
    token: arbitrum.tokens.USDC,
    denomination: CHAINLINK_USD,
    feed: '0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3',
  },
  {
    token: arbitrum.tokens.WSTETH,
    denomination: CHAINLINK_ETH,
    feed: '0xb523AE262D20A936BC152e6023996e46FDC2A95D',
  },
  {
    token: arbitrum.tokens.WBTC,
    denomination: CHAINLINK_BTC,
    feed: '0x0017abAc5b6f291F9164e35B1234CA1D697f9CF4',
  },
  {
    token: arbitrum.tokens.KNC,
    denomination: CHAINLINK_USD,
    feed: '0xbF539d4c2106dd4D9AB6D56aed3d9023529Db145',
  },
  {
    token: arbitrum.tokens.LUSD,
    denomination: CHAINLINK_USD,
    feed: '0x0411D28c94d85A36bC72Cb0f875dfA8371D8fFfF',
  },
  {
    token: arbitrum.tokens.DPX,
    denomination: CHAINLINK_USD,
    feed: '0xc373B9DB0707fD451Bc56bA5E9b029ba26629DF0',
  },
  {
    token: arbitrum.tokens.USDC,
    denomination: CHAINLINK_USD,
    feed: '0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3',
  },
  {
    token: arbitrum.tokens.AAVE,
    denomination: CHAINLINK_USD,
    feed: '0xaD1d5344AaDE45F43E596773Bcc4c423EAbdD034',
  },
  {
    token: arbitrum.tokens.RPL,
    denomination: CHAINLINK_USD,
    feed: '0xF0b7159BbFc341Cc41E7Cb182216F62c6d40533D',
  },
  {
    token: arbitrum.tokens.ARB,
    denomination: CHAINLINK_USD,
    feed: '0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6',
  },
  {
    token: arbitrum.tokens.GNS,
    denomination: CHAINLINK_USD,
    feed: '0xE89E98CE4E19071E59Ed4780E0598b541CE76486',
  },
  {
    token: arbitrum.tokens.COMP,
    denomination: CHAINLINK_USD,
    feed: '0xe7C53FFd03Eb6ceF7d208bC4C13446c76d1E5884',
  },
  {
    token: arbitrum.tokens.BAL,
    denomination: CHAINLINK_USD,
    feed: '0xBE5eA816870D11239c543F84b71439511D70B94f',
  },
  {
    token: arbitrum.tokens.MKR,
    denomination: CHAINLINK_USD,
    feed: '0xdE9f0894670c4EFcacF370426F10C3AD2Cdf147e',
  },
  {
    token: arbitrum.tokens.FRAX,
    denomination: CHAINLINK_USD,
    feed: '0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8',
  },
  {
    token: arbitrum.tokens.MAGIC,
    denomination: CHAINLINK_USD,
    feed: '0x47E55cCec6582838E173f252D08Afd8116c2202d',
  },
  {
    token: arbitrum.tokens.YFI,
    denomination: CHAINLINK_USD,
    feed: '0x745Ab5b69E01E2BE1104Ca84937Bb71f96f5fB21',
  },
  {
    token: arbitrum.tokens.CRV,
    denomination: CHAINLINK_USD,
    feed: '0xaebDA2c976cfd1eE1977Eac079B4382acb849325',
  },
  {
    token: arbitrum.tokens.RDNT,
    denomination: CHAINLINK_USD,
    feed: '0x20d0Fcab0ECFD078B036b6CAf1FaC69A6453b352',
  },
  {
    token: arbitrum.tokens.LINK,
    denomination: CHAINLINK_USD,
    feed: '0x86E53CF1B870786351Da77A57575e79CB55812CB',
  },
  {
    token: arbitrum.tokens.USDT,
    denomination: CHAINLINK_USD,
    feed: '0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7',
  },
  {
    token: arbitrum.tokens.TUSD,
    denomination: CHAINLINK_USD,
    feed: '0x6fAbee62266Da6686EE2744C6f15bb8352d2f28D',
  },
  {
    token: arbitrum.tokens.GMX,
    denomination: CHAINLINK_USD,
    feed: '0xDB98056FecFff59D032aB628337A4887110df3dB',
  },
  {
    token: arbitrum.tokens.DAI,
    denomination: CHAINLINK_USD,
    feed: '0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB',
  },
  {
    token: arbitrum.tokens.JOE,
    denomination: CHAINLINK_USD,
    feed: '0x04180965a782E487d0632013ABa488A472243542',
  },
  {
    token: arbitrum.tokens.WBTC,
    denomination: CHAINLINK_USD,
    feed: '0xd0C7101eACbB49F3deCcCc166d238410D6D46d57',
  },
  {
    token: arbitrum.tokens.CBETH,
    denomination: CHAINLINK_ETH,
    feed: '0xa668682974E3f121185a3cD94f00322beC674275',
  },
  {
    token: arbitrum.tokens.DODO,
    denomination: CHAINLINK_USD,
    feed: '0xA33a06c119EC08F92735F9ccA37e07Af08C4f281',
  },
  {
    token: arbitrum.tokens.MIMATIC,
    denomination: CHAINLINK_USD,
    feed: '0x59644ec622243878d1464A9504F9e9a31294128a',
  },
  {
    token: arbitrum.tokens.USDD,
    denomination: CHAINLINK_USD,
    feed: '0x4Ee1f9ec1048979930aC832a3C1d18a0b4955a02',
  },
  {
    token: arbitrum.tokens.SUSHI,
    denomination: CHAINLINK_USD,
    feed: '0xb2A8BA74cbca38508BA1632761b56C897060147C',
  },
  {
    token: arbitrum.tokens.UNI,
    denomination: CHAINLINK_USD,
    feed: '0x9C917083fDb403ab5ADbEC26Ee294f6EcAda2720',
  },
  {
    token: arbitrum.tokens.SPELL,
    denomination: CHAINLINK_USD,
    feed: '0x383b3624478124697BEF675F07cA37570b73992f',
  },
  {
    token: arbitrum.tokens.FXS,
    denomination: CHAINLINK_USD,
    feed: '0x36a121448D74Fa81450c992A1a44B9b7377CD3a5',
  },
  {
    token: arbitrum.tokens.PREMIA,
    denomination: CHAINLINK_USD,
    feed: '0x50db815D3c4B869F89925690E936ED85b0b76075',
  },
  {
    token: arbitrum.tokens.SOL,
    denomination: CHAINLINK_USD,
    feed: '0x24ceA4b8ce57cdA5058b924B9B9987992450590c',
  },
  {
    token: arbitrum.tokens.OP,
    denomination: CHAINLINK_USD,
    feed: '0x205aaD468a11fd5D34fA7211bC6Bad5b3deB9b98',
  },
];

export const arbitrumGoerliFeeds = [
  {
    token: arbitrumGoerli.tokens.testWETH, // testWETH
    denomination: CHAINLINK_USD,
    feed: '0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08',
  },
  {
    token: CHAINLINK_ETH,
    denomination: CHAINLINK_USD,
    feed: '0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08',
  },
  {
    token: arbitrumGoerli.tokens.WBTC,
    denomination: CHAINLINK_USD,
    feed: '0x6550bc2301936011c1334555e62A87705A81C12C',
  },
  {
    token: arbitrumGoerli.tokens.LINK,
    denomination: CHAINLINK_USD,
    feed: '0xd28Ba6CA3bB72bF371b80a2a0a33cBcf9073C954',
  },
  {
    token: arbitrumGoerli.tokens.USDC,
    denomination: CHAINLINK_USD,
    feed: '0x1692Bdd32F31b831caAc1b0c9fAF68613682813b',
  },
];
