import React from "react";
import styled from "styled-components";
import logo from "../../assets/svg/logo.svg";

import * as S from "./styles";

const Header = () => {
  return (
    <S.Header>
      <Navigation>
        <Logo src={logo} alt={"logo"} />
        <Router>
          <li>Home</li>
          <li>Swap</li>
        </Router>
      </Navigation>
      {/* Export out to Web3 component */}
      <Button onClick={() => alert("hi")}>Connect a wallet</Button>
    </S.Header>
  );
};

const Navigation = styled.div`
  display: flex;
  align-self: center;
`;

const Router = styled.ul`
  & li {
    background: #ff00ff;
    margin: 30px;
    display: inline;
  }
`;

const Logo = styled.img`
  color: #eee;
  width: 170px;
  height: 50px;
`;

const Button = styled.button`
  align-self: center;
  padding: 8px;
  border: 2px solid ${props => props.theme.primaryPink};
  border-radius: 15px;
  &:hover {
    cursor: pointer;
    background-color: #eee;
  }
`;

export default Header;
