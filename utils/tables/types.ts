import { ContractType } from '../deployment/types';

export interface TableData {
  categories: {
    [key: string]: {
      name: string;
      chain: string;
      sections: Section[];
      displayHeader: () => string;
    };
  };
}

type Section = {
  name: string;
  contracts: Contract[];
};

export type Contract = {
  name: string;
  description: string;
  type?: ContractType;
  address: string;
  commitHash?: string;
  etherscanUrl: string;
  filePath?: string;
  displayAddress: () => string;
  displayEtherscanUrl: () => string;
  displayFilePathUrl?: () => string;
};
