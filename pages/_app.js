import "bootstrap/dist/css/bootstrap.min.css";
import "../styles/offcanvas-navbar.css";
import "../styles/globals.css";
import "../styles/modals.css";
import "../styles/stakebutton.css";
import "sf-font";
import { connectWallet } from "../components/config";

import { useState, useEffect } from "react";

function MyApp({ Component, pageProps }) {
  const [status, getStatus] = useState("Connect Wallet");

  async function connect() {
    let walletaddress = await connectWallet().then((output) => {
      return output.connection.account.address;
    });
    localStorage.setItem("wallet", walletaddress);
  }

  useEffect(() => {
    setInterval(() => {
      let walletid = localStorage.getItem("wallet");
      if (walletid != null) {
        getStatus("Connected");
      }
    }, 4000);
  }, []);

  useEffect(() => {
    require("bootstrap/dist/js/bootstrap.bundle.min.js");
  }, []);

  return (
    <div>
      <header className="">
        <div className="container">
          <div className="d-flex flex-wrap align-items-center justify-content-center justify-content-lg-start">
            <ul
              className="nav col-12 col-lg me-lg mb-2 justify-content-left mb-md-0"
              style={{ fontSize: "20px", fontWeight: "bold" }}
            >
              <li>
                <a href="#" className="nav-link px-5 text-white">
                  Gs Stake
                </a>
              </li>
            </ul>
            <button className="btn btn-md btn-primary" onClick={connect}>
              {status}
            </button>
          </div>
        </div>
      </header>
      <Component {...pageProps} />
    </div>
  );
}

export default MyApp;
