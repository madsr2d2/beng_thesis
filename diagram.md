# Some markdown

## Some more markdown

## Mermaid with custom title/desc

 ```mermaid
  %%{init: {'flowchart': {'defaultRenderer': 'elk', 'elk': {'algorithm': 'layered'}}}}%%

graph TD
   Start([Start CAN Bus])

   subgraph FRAME_CONFIG["📋 Frame Configuration"]
      Config[Configure Frame]
      ARB{Frame Type?}
      Config --> ARB
      ARB -->|Data Frame| DataPath[Arbitration Field]
      ARB -->|Remote Frame| RemotePath[Remote Request]
   end

   subgraph FRAME_BUILD["🏗️ Frame Building"]
      DataPath --> DLC[Add DLC]
      RemotePath --> DLC
      DLC --> FDF{CAN FD?}
      FDF -->|Yes| FDCTRL[Add FDF/BRS/ESI]
      FDF -->|No| CTRL[Control Field]
      FDCTRL --> AddData[Add Data Field]
      CTRL --> AddData
   end

   subgraph ENCODING["🔐 Encoding & Protection"]
      AddData --> CalcCRC[Calculate CRC]
      CalcCRC --> StuffBits[Apply Bit Stuffing]
      StuffBits --> AddACK[Add ACK Field]
      AddACK --> AddEOF[Add EOF Field]
   end

   subgraph TRANSMISSION["📡 Transmission & Monitoring"]
      AddEOF --> Transmit[Transmit Frame]
      Transmit --> Monitor[Monitor Bus]
      Monitor --> Error{Error Detected?}
   end

   subgraph ERROR_HANDLING["⚠️ Error Handling"]
      Error -->|Yes| ErrorFrame[Send Error Frame]
      Error -->|No| Success([Frame Transmitted])
      ErrorFrame --> Recovery[Recovery Routine]
   end

   Start --> FRAME_CONFIG
   FRAME_CONFIG --> FRAME_BUILD
   FRAME_BUILD --> ENCODING
   ENCODING --> TRANSMISSION
   TRANSMISSION --> ERROR_HANDLING
   Recovery --> Monitor
```

dasda
