# Learn how to create NFTs on Tezos using Taquito and Pinata

##### This is a tutorial dapp to show how to create NFTs on Tezos with Taquito and Pinata

Structure of the project

- Frontend folder: contains the dapp users interact with to provide a picture, title and description for their NFT
- Backend folder: contains the server app to pin the picture and the metadata to Pinata (IPFS)
- Contract: contains the FA2 contract recording the NFTs

Getting started:

- For the frontend dapp:

```
npm install
npm run dev
```

- For the backend dapp:

```
npm install
npm run dev
```

- For the contract:
  The code of the contract can be copy-pasted into the [Ligo web IDE](https://ide.ligolang.org/) and originated from there. The default storage is available in a comment block at the bottom of the contract.
- Pinata: you will need an account on [Pinata](https://pinata.cloud/pinmanager) and [API keys](https://pinata.cloud/keys). Keep your API keys secret!
