import styled from "styled-components";

export const Toggle = styled.div`
  display: flex;
  flex-direction: row;
  background-color: ${props => props.theme.toggleSecondary};
  border-radius: 25px;
  width: 100%;
  justify-content: center;
`;