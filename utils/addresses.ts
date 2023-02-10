export type Token = { address: string; decimals: number; symbol: string };

// NOTE: Ethereum Addresses Only
// prettier-ignore
export const tokens: { [symbol: string]: Token } =  {
    'BNT': { address: '0x1f573d6fb3f13d689ff844b4ce37794d79a7ff1c', decimals: 18, symbol: 'BNT' },
    'CRV': { address: '0xD533a949740bb3306d119CC777fa900bA034cd52', decimals: 18, symbol: 'CRV' },
    'AMP': { address: '0xff20817765cb7f73d4bde2e66e067e58d11095c2', decimals: 18, symbol: 'AMP' },
    'FXS': { address: '0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0', decimals: 18, symbol: 'FXS' },
    'AXS': { address: '0xbb0e17ef65f82ab018d8edd776e8dd940327b28b', decimals: 18, symbol: 'AXS' },
    'DAI': { address: '0x6b175474e89094c44da98b954eedeac495271d0f', decimals: 18, symbol: 'DAI' },
    'USDC': { address: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48', decimals: 6, symbol: 'USDC' },
    'USDT': { address: '0xdAC17F958D2ee523a2206206994597C13D831ec7', decimals: 6, symbol: 'USDT' },
    'WBTC': { address: '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599', decimals: 8, symbol: 'WBTC' },
    'WETH': { address: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2', decimals: 18, symbol: 'WETH' },
    'AAVE': { address: '0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9', decimals: 18, symbol: 'AAVE' },
    'COMP': { address: '0xc00e94cb662c3520282e6f5717214004a7f26888', decimals: 18, symbol: 'COMP' },
    'BOND': { address: '0x0391d2021f89dc339f60fff84546ea23e337750f', decimals: 18, symbol: 'BOND' },
    'MATIC': { address: '0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0', decimals: 18, symbol: 'MATIC' },
    'ALPHA': { address: '0xa1faa113cbe53436df28ff0aee54275c13b40975', decimals: 18, symbol: 'ALPHA' }
}
