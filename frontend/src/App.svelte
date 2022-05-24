<script lang="ts">
  import { onMount } from "svelte";
  import { TezosToolkit, MichelCodecPacker } from "@taquito/taquito";
  import { char2Bytes, bytes2Char } from "@taquito/utils";
  import { BeaconWallet } from "@taquito/beacon-wallet";
  import { NetworkType } from "@airgap/beacon-sdk";

  let Tezos: TezosToolkit;
  let wallet: BeaconWallet;
  const walletOptions = {
    name: "Illic et Numquam",
    preferredNetwork: NetworkType.HANGZHOUNET
  };
  let userAddress: string;
  let files, title, description;

  if (process.env.NODE_ENV === "dev") {
    title = "uranus";
    description = "this is Uranus";
  }

  const rpcUrl = "https://api.hangzhou2net.tzkt.io/";
  const serverUrl =
    process.env.NODE_ENV !== "production"
      ? "http://localhost:8080"
      : "https://my-cool-backend-app.com";
  const contractAddress = "KT1VbJAzSAHQMvf5HC9zfEVMPbT2UcBvaMXb";
  let nftStorage = undefined;
  let userNfts: { tokenId: number; ipfsHash: string }[] = [];
  let pinningMetadata = false;
  let mintingToken = false;
  let newNft:
    | undefined
    | { imageHash: string; metadataHash: string; opHash: string };

  const getUserNfts = async (address: string) => {
    // finds user's NFTs
    const contract = await Tezos.wallet.at(contractAddress);
    nftStorage = await contract.storage();
    const getTokenIds = await nftStorage.reverse_ledger.get(address);
    if (getTokenIds) {
      userNfts = await Promise.all([
        ...getTokenIds.map(async id => {
          const tokenId = id.toNumber();
          const metadata = await nftStorage.token_metadata.get(tokenId);
          const tokenInfoBytes = metadata.token_info.get("");
          const tokenInfo = bytes2Char(tokenInfoBytes);
          return {
            tokenId,
            ipfsHash:
              tokenInfo.slice(0, 7) === "ipfs://" ? tokenInfo.slice(7) : null
          };
        })
      ]);
    }
  };

  const connect = async () => {
    if (!wallet) {
      wallet = new BeaconWallet(walletOptions);
    }

    try {
      await wallet.requestPermissions({
        network: {
          type: NetworkType.HANGZHOUNET,
          rpcUrl
        }
      });
      userAddress = await wallet.getPKH();
      Tezos.setWalletProvider(wallet);
      await getUserNfts(userAddress);
    } catch (err) {
      console.error(err);
    }
  };

  const disconnect = () => {
    wallet.client.destroy();
    wallet = undefined;
    userAddress = "";
  };

  const upload = async () => {
    try {
      pinningMetadata = true;
      const data = new FormData();
      data.append("image", files[0]);
      data.append("title", title);
      data.append("description", description);
      data.append("creator", userAddress);

  
    
          pinningMetadata = false;
          mintingToken = true;
          // saves NFT on-chain
          const contract = await Tezos.wallet.at(contractAddress);
          const op = await contract.methods
            .mint(char2Bytes("ipfs://QmY1nfe4KgV95y5XHTPU9mBxEga2Z541wmfg1b5dXdPCxH"), userAddress)
            .send();
          console.log("Op hash:", op.opHash);
          await op.confirmation();

          newNft = {
            imageHash: 'QmY1nfe4KgV95y5XHTPU9mBxEga2Z541wmfg1b5dXdPCxH',
            metadataHash: 'QmY1nfe4KgV95y5XHTPU9mBxEga2Z541wmfg1b5dXdPCxH',
            opHash: op.opHash
          };

          files = undefined;
          title = "";
          description = "";

          // refreshes storage
          await getUserNfts(userAddress);

    } catch (error) {
      console.log(error);
    } finally {
      pinningMetadata = false;
      mintingToken = false;
    }
  };

  onMount(async () => {
    Tezos = new TezosToolkit(rpcUrl);
    Tezos.setPackerProvider(new MichelCodecPacker());
    wallet = new BeaconWallet(walletOptions);
    if (await wallet.client.getActiveAccount()) {
      userAddress = await wallet.getPKH();
      Tezos.setWalletProvider(wallet);
      await getUserNfts(userAddress);
    }
  });
</script>

<style lang="scss">
  $tezos-blue: #2e7df7;

  h1 {
    font-size: 3rem;
    font-family: "Roman-SD";
  }

  button {
    padding: 20px;
    font-size: 1rem;
    border: solid 3px #d1d5db;
    background-color: #e5e7eb;
    border-radius: 10px;
    cursor: pointer;
  }

  .roman {
    text-transform: uppercase;
    font-family: "Roman-SD";
    font-weight: bold;
  }

  .container {
    font-size: 1.3rem;
    & > div {
      padding: 20px;
    }

    label {
      display: flex;
      flex-direction: column;
      text-align: left;
    }

    input,
    textarea {
      padding: 10px;
    }

    .user-nfts {
      display: flex;
      justify-content: center;
      align-items: center;
    }
  }
</style>

<main>
  <div class="container">
    <h1>Illic Et Numquam</h1>
    {#if userAddress}
      <div>
        <div class="user-nfts">
          Your NFTs:
          {#if nftStorage}
            [ {#each userNfts.reverse() as nft, index}
              <a
                href={`https://cloudflare-ipfs.com/ipfs/${nft.ipfsHash}`}
                target="_blank"
                rel="noopener noreferrer nofollow"
              >
                {nft.tokenId}
              </a>
              {#if index < userNfts.length - 1}
                <span>,&nbsp;</span>
              {/if}
            {/each} ]
          {/if}
        </div>
        <br />
        <button class="roman" on:click={disconnect}>Disconnect</button>
      </div>
      {#if newNft}
        <div>Your NFT has been successfully minted!</div>
        <div>
          <a
            href={`https://cloudflare-ipfs.com/ipfs/${newNft.imageHash}`}
            target="_blank"
            rel="noopener noreferrer nofollow"
          >
            Link to your picture
          </a>
        </div>
        <div>
          <a
            href={`https://cloudflare-ipfs.com/ipfs/${newNft.metadataHash}`}
            target="_blank"
            rel="noopener noreferrer nofollow"
          >
            Link to your metadata
          </a>
        </div>
        <div>
          <a
            href={`https://better-call.dev/edo2net/opg/${newNft.opHash}/contents `}
            target="_blank"
            rel="noopener noreferrer nofollow"
          >
            Link to the operation details
          </a>
        </div>
        <div>
          <button class="roman" on:click={() => (newNft = undefined)}>
            Mint a new NFT
          </button>
        </div>
      {:else}
        <div>
          <div>Select your picture</div>
          <br />
          <input type="file" bind:files />
        </div>
        <div>
          <label for="image-title">
            <span>Title:</span>
            <input type="text" id="image-title" bind:value={title} />
          </label>
        </div>
        <div>
          <label for="image-description">
            <span>Description:</span>
            <textarea
              id="image-description"
              rows="4"
              bind:value={description}
            />
          </label>
        </div>
        <div>
          {#if pinningMetadata}
            <button class="roman"> Saving your image... </button>
          {:else if mintingToken}
            <button class="roman"> Minting your NFT... </button>
          {:else}
            <button class="roman" on:click={upload}> Upload </button>
          {/if}
        </div>
      {/if}
    {:else}
      <div class="roman">Create an NFT with your pictures</div>
      <button class="roman" on:click={connect}>Connect your wallet</button>
    {/if}
  </div>
</main>
