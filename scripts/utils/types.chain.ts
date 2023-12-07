export enum ChainID {
  Ethereum = 1,
  Goerli = 5,
  Arbitrum = 42161,
  ArbitrumGoerli = 421613,
  ArbitrumNova = 42170,
}

export const ChainName: { [chainId: number]: string } = {
  [ChainID.Ethereum]: 'Ethereum',
  [ChainID.Goerli]: 'Goerli',
  [ChainID.Arbitrum]: 'Arbitrum',
  [ChainID.ArbitrumGoerli]: 'Arbitrum Goerli',
  [ChainID.ArbitrumNova]: 'Arbitrum Nova',
};

export const BlockExplorerUrl: { [chainId: number]: string } = {
  [ChainID.Ethereum]: 'https://etherscan.io',
  [ChainID.Goerli]: 'https://goerli.etherscan.io',
  [ChainID.Arbitrum]: 'https://arbiscan.io',
  [ChainID.ArbitrumGoerli]: 'https://goerli.arbiscan.io',
  [ChainID.ArbitrumNova]: 'https://nova.arbiscan.io',
};

export const DeploymentPath: { [chainId: number]: string } = {
  [ChainID.Arbitrum]: 'deployments/arbitrum/',
  [ChainID.ArbitrumGoerli]: 'deployments/arbitrumGoerli/',
  [ChainID.ArbitrumNova]: 'deployments/arbitrumNova/',
};
