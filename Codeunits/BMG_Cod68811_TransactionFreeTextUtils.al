codeunit 68811 "BMG Transaction FreeText Utils" implements "BMG ITransactionFreeTextUtils"
{
    var
        SetupInitialized: Boolean;
        IsTransferFreeText: Boolean;

    #region Setup
    internal procedure GetTransferFreeTextSetup(StoreNo: Code[20]; POSTerminalNo: Code[20]): Boolean
    var
        Store: Record "LSC Store";
        POSTerminal: Record "LSC POS Terminal";
    begin
        if SetupInitialized then
            exit(IsTransferFreeText);

        if Store.Get(StoreNo) and (Store."Functionality Profile" <> '') then
            exit(GetTransferFreeTextSetup(Store."Functionality Profile"));

        if POSTerminal.Get(POSTerminalNo) and (POSTerminal."Functionality Profile" <> '') then
            exit(GetTransferFreeTextSetup(POSTerminal."Functionality Profile"));

        exit(false);
    end;

    internal procedure GetTransferFreeTextSetup(ProfileID: Code[20]): Boolean
    var
        POSFunctionalityProfile: Record "LSC POS Func. Profile";
    begin
        if POSFunctionalityProfile.Get(ProfileID) then
            IsTransferFreeText := POSFunctionalityProfile."Transfer Free Texts Into CO/SO"
        else
            IsTransferFreeText := false;

        SetupInitialized := true;
        exit(IsTransferFreeText);
    end;

    internal procedure SetSetupInitialized(SetupRead2: Boolean; IsTrasnferFreeText2: Boolean);
    begin
        SetupInitialized := SetupRead2;
        IsTransferFreeText := IsTrasnferFreeText2;
    end;
    #endregion

    #region AddTransTextLines
    internal procedure AddTransTextLinesToSalesDocument(PosTransaction: Record "LSC POS Transaction"; SalesHeader: Record "Sales Header"; ParentLine: Integer)
    var
        PosTransLine: Record "LSC POS Trans. Line";
        SalesLine: Record "Sales Line";
        IsHandled: Boolean;
    begin
        OnBeforeAddPOSTransTextLinesToSalesDocument(PosTransaction, SalesHeader, ParentLine, IsHandled);
        if IsHandled then
            exit;

        AddTransTextLinesToSalesDocument(PosTransLine, SalesLine, PosTransaction, SalesHeader, ParentLine);
    end;

    internal procedure AddTransTextLinesToSalesDocument(var PosTransLine: Record "LSC POS Trans. Line"; var SalesLine: Record "Sales Line"; PosTransaction: Record "LSC POS Transaction"; SalesHeader: Record "Sales Header"; ParentLine: Integer)
    var
        POSTransLine2: Record "LSC POS Trans. Line";
        POSTransLineTemp: Record "LSC POS Trans. Line" temporary;
    begin
        if not GetTransferFreeTextSetup(PosTransaction."Store No.", PosTransaction."POS Terminal No.") then
            exit;

        if PosTransLine.IsTemporary() then begin
            POSTransLineTemp.Copy(PosTransLine, true);
            AddTransTextLinesToSalesDocument(POSTransLineTemp, SalesLine, SalesHeader, ParentLine, PosTransaction."Receipt No.");
        end else
            AddTransTextLinesToSalesDocument(PosTransLine2, SalesLine, SalesHeader, ParentLine, PosTransaction."Receipt No.");
    end;

    local procedure AddTransTextLinesToSalesDocument(var PosTransLine: Record "LSC POS Trans. Line"; var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header"; ParentLine: Integer; ReceiptNo: Code[20])
    begin
        if not FindFreeTextTransLines(PosTransLine, ReceiptNo, ParentLine) then
            exit;

        repeat
            ParentLine += 100;
            PopulateSalesLineFromFreeText(SalesLine, SalesHeader, ParentLine, PosTransLine.Description);
            SalesLine.Insert(true);
        until PosTransLine.Next() = 0;
    end;

    internal procedure AddTransTextLinesToSalesDocument(TransactionHeader: Record "LSC Transaction Header"; SalesHeader: Record "Sales Header"; ParentLine: Integer; NewParentLine: Integer)
    var
        TransInfocodeEntry: Record "LSC Trans. Infocode Entry";
        SalesLine: Record "Sales Line";
        IsHandled: boolean;
    begin
        OnBeforeAddTransTextLinesToSalesDocument(TransactionHeader, SalesHeader, ParentLine, NewParentLine, IsHandled);
        if IsHandled then
            exit;

        if not GetTransferFreeTextSetup(TransactionHeader."Store No.", TransactionHeader."POS Terminal No.") then
            exit;

        AddTransTextLinesToSalesDocument(TransInfocodeEntry, SalesLine, TransactionHeader, SalesHeader, ParentLine, NewParentLine);
    end;

    internal procedure AddTransTextLinesToSalesDocument(var TransInfocodeEntry: Record "LSC Trans. Infocode Entry"; var SalesLine: Record "Sales Line"; TransactionHeader: Record "LSC Transaction Header";
                    SalesHeader: Record "Sales Header"; ParentLine: Integer; NewParentLine: Integer)
    begin
        if not FindFreeTextTransLines(TransInfocodeEntry, TransactionHeader, ParentLine) then
            exit;

        repeat
            NewParentLine += 100;
            PopulateSalesLineFromFreeText(SalesLine, SalesHeader, NewParentLine, TransInfocodeEntry.Information);
            SalesLine.Insert(true);
        until TransInfocodeEntry.Next() = 0;
    end;

    internal procedure AddTransTextLinesToCustomerOrder(PosTransaction: Record "LSC POS Transaction"; DocumentID: code[20]; var CustomerOrderLineTemp: Record "LSC Customer Order Line" temporary)
    var
        PosTransLine: Record "LSC POS Trans. Line";
        IsHandled: boolean;
    begin
        OnBeforeAddTransTextLinesToCustomerOrder(PosTransaction, DocumentID, CustomerOrderLineTemp, IsHandled);
        if IsHandled then
            exit;

        if not GetTransferFreeTextSetup(PosTransaction."Store No.", PosTransaction."POS Terminal No.") then
            exit;

        AddTransTextLinesToCustomerOrder(PosTransaction, DocumentID, PosTransLine, CustomerOrderLineTemp);
    end;

    internal procedure AddTransTextLinesToCustomerOrder(PosTransaction: Record "LSC POS Transaction"; DocumentID: code[20]; var PosTransLine: Record "LSC POS Trans. Line"; var CustomerOrderLineTemp: Record "LSC Customer Order Line" temporary)
    var
        LineNo: Integer;
    begin
        if FindFreeTextTransLines(PosTransLine, PosTransaction."Receipt No.", 0) then
            repeat
                LineNo += 100;
                PopulateCustomerOrderLine(CustomerOrderLineTemp, DocumentID, LineNo, PosTransLine.Description);
                CustomerOrderLineTemp.Insert();
            until PosTransLine.Next() = 0;

        if FindAllLinkedFreeTextTransLines(PosTransLine, PosTransaction."Receipt No.") then
            repeat
                PopulateCustomerOrderLine(CustomerOrderLineTemp, DocumentID, PosTransLine."Line No.", PosTransLine.Description);
                CustomerOrderLineTemp.Insert();
            until PosTransLine.Next() = 0;
    end;
    #endregion

    #region Filters
    local procedure FindAllLinkedFreeTextTransLines(var PosTransLine: Record "LSC POS Trans. Line"; ReceiptNo: Code[20]): Boolean
    begin
        PosTransLine.SetLoadFields("Description");
        PosTransLine.SetRange("Receipt No.", ReceiptNo);
        PosTransLine.SetRange("Entry Type", PosTransLine."Entry Type"::FreeText);
        PosTransLine.SetRange("Text Type", PosTransLine."Text Type"::"Freetext Input");
        PosTransLine.SetFilter("Parent Line", '<>%1', 0);
        exit(PosTransLine.FindSet());
    end;

    local procedure FindFreeTextTransLines(var PosTransLine: Record "LSC POS Trans. Line"; ReceiptNo: Code[20]; ParentLine: integer): Boolean
    begin
        PosTransLine.SetLoadFields("Description");
        PosTransLine.SetRange("Receipt No.", ReceiptNo);
        PosTransLine.SetRange("Entry Type", PosTransLine."Entry Type"::FreeText);
        PosTransLine.SetRange("Text Type", PosTransLine."Text Type"::"Freetext Input");
        PosTransLine.SetRange("Parent Line", ParentLine);
        exit(PosTransLine.FindSet());
    end;

    local procedure FindFreeTextTransLines(var TransInfocodeEntry: Record "LSC Trans. Infocode Entry"; TransactionHeader: Record "LSC Transaction Header"; ParentLine: Integer): Boolean
    begin
        TransInfocodeEntry.SetLoadFields("Information");
        TransInfocodeEntry.SetRange("Store No.", TransactionHeader."Store No.");
        TransInfocodeEntry.SetRange("POS Terminal No.", TransactionHeader."POS Terminal No.");
        TransInfocodeEntry.SetRange("Transaction No.", TransactionHeader."Transaction No.");
        TransInfocodeEntry.SetRange("Text Type", TransInfocodeEntry."Text Type"::"Freetext Input");
        TransInfocodeEntry.SetRange(ParentLine, ParentLine);
        exit(TransInfocodeEntry.FindSet());
    end;
    #endregion

    #region Populate Tables
    internal procedure PopulateSalesLineFromFreeText(var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header"; LineNo: Integer; Description: text)
    var
    begin
        SalesLine."Document Type" := SalesHeader."Document Type";
        SalesLine."Document No." := SalesHeader."No.";
        SalesLine."Line No." := LineNo;
        SalesLine.Validate(Type, SalesLine.Type::" ");
        SalesLine.Validate(Description, Description);
        OnAfterPopulateSalesLineFromFreeText(SalesLine, SalesHeader, LineNo, Description);
    end;

    internal procedure PopulateCustomerOrderLine(var CustomerOrderLineTemp: Record "LSC Customer Order Line" temporary; DocumentID: code[20]; LineNo: Integer; Description: Text)
    begin
        CustomerOrderLineTemp.Init();
        CustomerOrderLineTemp."Document ID" := DocumentID;
        CustomerOrderLineTemp."Line No." := LineNo;
        CustomerOrderLineTemp."Line Type" := CustomerOrderLineTemp."Line Type"::FreeText;
        CustomerOrderLineTemp."Item Description" := Description;
        OnAfterPopulateCOLineFromFreeText(CustomerOrderLineTemp, DocumentID, LineNo, Description);
    end;
    #endregion

    #region Event Publishers
    [IntegrationEvent(false, false)]
    local procedure OnBeforeAddPOSTransTextLinesToSalesDocument(PosTransaction: Record "LSC POS Transaction"; SalesHeader: Record "Sales Header"; var ParentLine: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeAddTransTextLinesToSalesDocument(TransactionHeader: Record "LSC Transaction Header"; SalesHeader: Record "Sales Header"; var ParentLine: Integer; var NewParentLine: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeAddTransTextLinesToCustomerOrder(PosTransaction: Record "LSC POS Transaction"; DocumentID: code[20]; var CustomerOrderLineTemp: Record "LSC Customer Order Line" temporary; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPopulateSalesLineFromFreeText(var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header"; LineNo: Integer; Description: Text)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPopulateCOLineFromFreeText(var CustomerOrderLineTemp: Record "LSC Customer Order Line" temporary; DocumentID: code[20]; LineNo: Integer; Description: Text)
    begin
    end;
    #endregion
}