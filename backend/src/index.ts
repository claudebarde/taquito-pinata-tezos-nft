import express from "express";
import pinataSDK from "@pinata/sdk";
import fs from "fs";
const cors = require("cors");
const multer = require("multer");

const app = express();
const upload = multer({ dest: "uploads/" });
const port = process.env.NODE_ENV === "production" ? process.env.PORT : 8080; // default port to listen
let pinata: any;
if (process.env.NODE_ENV === "production") {
  pinata = pinataSDK(process.env.PINATA_API_KEY, process.env.PINATA_SECRET_KEY);
} else {
  const PinataKeys = require("./PinataKeys");
  pinata = pinataSDK(PinataKeys.apiKey, PinataKeys.apiSecret);
}

const corsOptions = {
  origin: ["http://localhost:8082", "https://my-cool-nft-app.com"],
  optionsSuccessStatus: 200 // some legacy browsers (IE11, various SmartTVs) choke on 204
};
app.use(cors(corsOptions));
app.use(express.json({ limit: "50mb" }));
app.use(
  express.urlencoded({ limit: "50mb", extended: true, parameterLimit: 50000 })
);

// defines a route handler for the default home page
app.get("/", (req, res) => {
  res.send("Hello developers!");
});

// handles minting
app.post("/mint", upload.single("image"), async (req, res) => {
  const multerReq = req as any;
  //console.log(multerReq.file, req.body);
  if (!multerReq.file) {
    res.status(500).json({ status: false, msg: "no file provided" });
  } else {
    const fileName = multerReq.file.filename;
    // tests Pinata authentication
    await pinata
      .testAuthentication()
      .catch((err: any) => res.status(500).json(JSON.stringify(err)));
    // creates readable stream
    const readableStreamForFile = fs.createReadStream(`./uploads/${fileName}`);
    const options: any = {
      pinataMetadata: {
        name: req.body.title.replace(/\s/g, "-"),
        keyvalues: {
          description: req.body.description
        }
      }
    };
    const pinnedFile = await pinata.pinFileToIPFS(
      readableStreamForFile,
      options
    );
    if (pinnedFile.IpfsHash && pinnedFile.PinSize > 0) {
      // remove file from server
      fs.unlinkSync(`./uploads/${fileName}`);
      // pins metadata
      const metadata = {
        name: req.body.title,
        description: req.body.description,
        symbol: "TUT",
        artifactUri: `ipfs://${pinnedFile.IpfsHash}`,
        displayUri: `ipfs://${pinnedFile.IpfsHash}`,
        creators: [req.body.creator],
        decimals: 0,
        thumbnailUri: "https://tezostaquito.io/img/favicon.png",
        is_transferable: true,
        shouldPreferSymbol: false
      };

      const pinnedMetadata = await pinata.pinJSONToIPFS(metadata, {
        pinataMetadata: {
          name: "TUT-metadata"
        }
      });

      if (pinnedMetadata.IpfsHash && pinnedMetadata.PinSize > 0) {
        res.status(200).json({
          status: true,
          msg: {
            imageHash: pinnedFile.IpfsHash,
            metadataHash: pinnedMetadata.IpfsHash
          }
        });
      } else {
        res
          .status(500)
          .json({ status: false, msg: "metadata were not pinned" });
      }
    } else {
      res.status(500).json({ status: false, msg: "file was not pinned" });
    }
  }
});

// starts the Express server
app.listen(port, () => {
  console.log(`server started at http://localhost:${port}`);
});
