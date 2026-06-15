codeunit 68809 "BMG CO Prepayment Invoice Mgt"
{
    Access = Internal;

    var
        COPrepaymentInvManPubl: Codeunit "BMG CO Prepay. Inv. Mgt Public";

    #region "Prepayment Invoice Man"

    #region SalesOrderPrePaymentInvoice

    #region PopulateAndPostSalesPrepaymentInvoice
    procedure PopulateAndPostSalesPrepaymentInvoice(Rec: Record "LSC Customer Order Header"; var SalesHeader: Record "Sales Header")
    begin
        if Rec."Prepayment Invoice Type" = Enum::"LSC Prepayment Invoice Type"::" " then
            exit;

        SetBasePrepaymentInvoiceInfo(SalesHeader);

        if SalesHeader."Prepayment %" = 0 then
            exit;

        SalesHeader.CalcFields("Amount Including VAT");
        if CreateAndPostPrePaymentInvoice(Rec, SalesHeader) then begin
            SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
            SalesHeader.CalcFields("Amount Including VAT");
            PostPrepaymentAgainstPrepaymentInvoice(Rec, SalesHeader."Amount Including VAT", SalesHeader);
            UpdatePendingPrepaymentSales(SalesHeader);
        end;
    end;
    #endregion PopulateAndPostSalesPrepaymentInvoice

    #region CreateAndPostPrePaymentInvoice
    local procedure CreateAndPostPrePaymentInvoice(Rec: Record "LSC Customer Order Header"; var SalesHeader: Record "Sales Header"): Boolean
    var
        SalesPostPrepayments: Codeunit "Sales-Post Prepayments";
        IsHandled: Boolean;
    begin
        COPrepaymentInvManPubl.OnBeforeCreateAndPostPrePaymentInvoice(Rec, SalesHeader, IsHandled);
        if IsHandled then
            exit(false);

        SalesPostPrepayments.SetDocumentType(Enum::"Sales Document Type"::Invoice.AsInteger());
        SalesPostPrepayments.SetSuppressCommit(true);
        SalesPostPrepayments.Run(SalesHeader);

        COPrepaymentInvManPubl.OnAfterCreatAndPostPrePaymentInvoice(Rec, SalesHeader);

        exit(true);
    end;
    #endregion CreateAndPostPrePaymentInvoice

    #region PostPrepaymentAgainstPrepaymentInvoice
    procedure PostPrepaymentAgainstPrepaymentInvoice(Rec: Record "LSC Customer Order Header"; PaymentAmount: Decimal; var SalesHeader: Record "Sales Header")
    var
        CustomerOrderPayment: Record "LSC Customer Order Payment";
        Store: Record "LSC Store";
        TenderType: Record "LSC Tender Type";
        IsHandled: Boolean;
        DocumentType: Enum "Gen. Journal Document Type";
        PaymentLabel: Label 'Payment';
    begin
        COPrepaymentInvManPubl.OnBeforePostGLForPrePaymentInvoice(IsHandled);
        if IsHandled then
            exit;

        Store.Get(Rec."Created at Store");
        // Find Payments and post them against Prepayment Invoice
        if PaymentAmount = 0 then begin
            CustomerOrderPayment.SetRange("Document ID", Rec."Document ID");
            CustomerOrderPayment.SetFilter(Type, '%1|%2', CustomerOrderPayment.Type::Payment, CustomerOrderPayment.Type::"Refunded on POS");
            CustomerOrderPayment.SetRange("Prepayment Document No.", '');
            if CustomerOrderPayment.FindSet() then begin
                repeat
                    TenderType.Get(CustomerOrderPayment."Store No.", CustomerOrderPayment."Tender Type");
                    if TenderType.Function <> TenderType.Function::Customer then begin
                        if CustomerOrderPayment.Type = CustomerOrderPayment.Type::Payment then
                            CreateAndPostGenLedgerForPrepaymentInvoice(SalesHeader, CustomerOrderPayment."Pre Approved Amount LCY", DocumentType::Payment, TenderType.Description)
                        else begin
                            Rec.CalcFields("Total Amount", "Finalised Amount");
                            PaymentAmount := Rec."Total Amount" - Rec."Finalised Amount";
                            CreateAndPostGenLedgerForPrepaymentInvoice(SalesHeader, PaymentAmount, DocumentType::Payment, TenderType.Description);
                        end;
                        CustomerOrderPayment."Prepayment Document Type" := SalesHeader."Document Type";
                        CustomerOrderPayment."Prepayment Document No." := SalesHeader."No.";
                        CustomerOrderPayment.Modify();
                    end;
                until CustomerOrderPayment.Next() = 0;
            end;
        end else begin
            // Unknown payment type, create a payment against Prepayment Invoice
            Clear(TenderType);
            TenderType.Description := PaymentLabel;
            CreateAndPostGenLedgerForPrepaymentInvoice(SalesHeader, PaymentAmount, DocumentType::Payment, TenderType.Description);
        end;
    end;
    #endregion PostPrepaymentAgainstPrepaymentInvoice

    #region CreateAndPostGenLedgerForPrepaymentInvoice
    local procedure CreateAndPostGenLedgerForPrepaymentInvoice(var SalesHeader: Record "Sales Header"; AmountToPost: Decimal; DocumentType: Enum "Gen. Journal Document Type"; TenderTypeDescription: Text)
    var
        GLAccount: Record "G/L Account";
        GenJnlLine: Record "Gen. Journal Line";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        IsHandled: Boolean;
        PrepaymentInvoiceAcc: Code[20];
        RefundText: Label 'Refund';
        Description: Text;
    begin
        PrepaymentInvoiceAcc := GetPrepaymentInvoiceAccountNo(SalesHeader."LSC Customer Order ID");
        GLAccount.Get(PrepaymentInvoiceAcc);
        if DocumentType = DocumentType::Payment then
            Description := StrSubstNo('%1 - %2', TenderTypeDescription, SalesHeader."Last Prepayment No.")
        else
            Description := StrSubstNo('%1 - %2', RefundText, SalesHeader."Last Prepmt. Cr. Memo No.");

        Clear(GenJnlLine);
        GenJnlLine.Init();
        GenJnlLine.Validate("Posting Date", SalesHeader."Posting Date");
        GenJnlLine.Validate("Document Date", SalesHeader."Document Date");

        GenJnlLine."Document Type" := DocumentType;

        if DocumentType = DocumentType::Payment then begin
            Description := StrSubstNo('%1 - %2', TenderTypeDescription, SalesHeader."Last Prepayment No.");
            GenJnlLine."Document No." := SalesHeader."Last Prepayment No.";
        end else begin
            Description := StrSubstNo('%1 - %2', RefundText, SalesHeader."Last Prepmt. Cr. Memo No.");
            GenJnlLine."Document No." := SalesHeader."Last Prepmt. Cr. Memo No.";
        end;

        GenJnlLine."Account Type" := Enum::"Gen. Journal Account Type"::Customer;
        GenJnlLine.Validate("Account No.", SalesHeader."Bill-to Customer No.");

        GenJnlLine.Validate("Payment Discount %", 0);
        GenJnlLine.Validate("Payment Terms Code", ''); // No payment terms for prepayment invoices

        GenJnlLine."Bal. Account Type" := GenJnlLine."Bal. Account Type"::"G/L Account";
        GenJnlLine.Validate("Bal. Account No.", PrepaymentInvoiceAcc);
        GenJnlLine.Validate("Bal. Gen. Posting Type", GLAccount."Gen. Posting Type");
        GenJnlLine.Validate("Bal. Gen. Bus. Posting Group", GLAccount."Gen. Bus. Posting Group");
        GenJnlLine.Validate("Bal. Gen. Prod. Posting Group", GLAccount."Gen. Prod. Posting Group");

        GenJnlLine.Validate("Currency Code", SalesHeader."Currency Code");
        GenJnlLine.Validate("Currency Factor", SalesHeader."Currency Factor");

        GenJnlLine.Description := CopyStr(Description, 1, MaxStrLen(GenJnlLine.Description));

        GenJnlLine.Validate(Quantity, 1);

        if DocumentType = DocumentType::Payment then
            GenJnlLine.Validate(Amount, -AmountToPost)
        else
            GenJnlLine.Validate(Amount, AmountToPost);

        if DocumentType = DocumentType::Payment then begin
            GenJnlLine."Applies-to Doc. Type" := GenJnlLine."Applies-to Doc. Type"::Invoice;
            GenJnlLine.Validate("Applies-to Doc. No.", SalesHeader."Last Prepayment No.");
        end else begin
            GenJnlLine."Applies-to Doc. Type" := GenJnlLine."Applies-to Doc. Type"::"Credit Memo";
            GenJnlLine.Validate("Applies-to Doc. No.", SalesHeader."Last Prepmt. Cr. Memo No.");
        end;

        GenJnlLine."LSC Customer Order No." := SalesHeader."LSC Customer Order ID";

        GenJnlLine."External Document No." := SalesHeader."External Document No.";

        IsHandled := false;
        COPrepaymentInvManPubl.OnBeforePostGLForPrePaymentInvoiceLine(GenJnlLine, IsHandled);
        if not IsHandled then
            GenJnlPostLine.RunWithCheck(GenJnlLine); // post payment against Prepayment Invoice;
    end;
    #endregion CreateAndPostGenLedgerForPrepaymentInvoice

    #region SetBasePrepaymentInvoiceInfo
    procedure SetBasePrepaymentInvoiceInfo(var SalesHeader: Record "Sales Header")
    begin
        SalesHeader.Validate("Prepmt. Payment Terms Code", '');
        SalesHeader.Validate("Prepmt. Pmt. Discount Date", 0D);
        SalesHeader.Validate("Prepayment Due Date", Today);
        SalesHeader.Validate("Compress Prepayment", true);
    end;
    #endregion SetBasePrepaymentInvoiceInfo

    #endregion SalesOrderPrePaymentInvoice

    #region CreditMemoPrePaymentInvoice

    #region PopulateAndPostSalesCreditPrepaymentInvoice
    procedure PopulateAndPostSalesCreditPrepaymentInvoice(Rec: Record "LSC Customer Order Header"; CreditAmount: Decimal; var SalesHeader: Record "Sales Header")
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
        SalesPostPrepmt: Codeunit "Sales-Post Prepayments";
        SalesManualReopen: Codeunit "Sales Manual Reopen";
    begin

        if Rec."Prepayment Invoice Type" = Enum::"LSC Prepayment Invoice Type"::" " then
            exit;

        SalesManualReopen.Run(SalesHeader);
        SalesHeader."Compress Prepayment" := true;
        SalesPostPrepmt.CreditMemo(SalesHeader);

        // refresh the Sales Header to get the correct cedit memo no.
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");

        SalesCrMemoHeader.Get(SalesHeader."Last Prepmt. Cr. Memo No.");
        SalesCrMemoHeader.CalcFields("Amount Including VAT");

        PostPrepaymentAgainstPrepaymentCreditInvoice(Rec, SalesHeader, SalesCrMemoHeader."Amount Including VAT");
        UpdatePendingPrepaymentSales(SalesHeader);
    end;

    procedure PostPrepaymentAgainstPrepaymentCreditInvoice(Rec: Record "LSC Customer Order Header"; var SalesHeader: Record "Sales Header"; CreditAmount: Decimal)
    var
        Store: Record "LSC Store";
        IsHandled: Boolean;
        DocumentType: Enum "Gen. Journal Document Type";
    begin
        if CreditAmount = 0 then
            exit;

        Store.Get(Rec."Created at Store");

        COPrepaymentInvManPubl.OnBeforePostPrepaymentAgainstPrepaymentCreditInvoice(Rec, SalesHeader, CreditAmount, IsHandled);
        if IsHandled then
            exit;

        CreateAndPostGenLedgerForPrepaymentInvoice(SalesHeader, CreditAmount, DocumentType::Refund, '');

        COPrepaymentInvManPubl.OnAfterPostPrepaymentAgainstPrepaymentCreditInvoice(Rec, SalesHeader, CreditAmount);
    end;
    #endregion PopulateAndPostSalesCreditPrepaymentInvoice

    #endregion CreditMemoPrePaymentInvoice    

    #endregion "Prepayment Invoice Man"

    #region Helpers and Common Functions

    #region IsCustomerOrderPrepaymentInvoiceMarked
    procedure IsCustomerOrderPrepaymentInvoiceMarked(CustomerOrderId: Code[20]): Boolean
    var
        CustomerOrderHeader: Record "LSC Customer Order Header";
        PostedCoHeader: Record "LSC Posted CO Header";
    begin
        if CustomerOrderId = '' then
            exit(false);

        if CustomerOrderHeader.Get(CustomerOrderId) then
            exit(CustomerOrderHeader."Prepayment Invoice Type" <> Enum::"LSC Prepayment Invoice Type"::" ")
        else
            if PostedCoHeader.Get(CustomerOrderId) then
                exit(PostedCoHeader."Prepayment Invoice Type" <> Enum::"LSC Prepayment Invoice Type"::" ");
    end;
    #endregion IsCustomerOrderPrepaymentInvoiceMarked

    #region UpdatePendingPrepaymentSales
    procedure UpdatePendingPrepaymentSales(SalesHeader: Record "Sales Header")
    var
        PrepaymentMgt: Codeunit "Prepayment Mgt.";
        StatusOfSalesOrderIsChangedTxt: Label 'The status of the sales order %1 is changed from Pending Prepayment to Release.', Comment = '%1 - sales order no.';
        UpdateSalesOrderStatusTxt: Label 'Update sales order status.';
    begin
        if not PrepaymentMgt.TestSalesPayment(SalesHeader) then begin
            Codeunit.Run(Codeunit::"Release Sales Document", SalesHeader);
            if SalesHeader.Status = SalesHeader.Status::Released then
                Session.LogMessage('0000254', StrSubstNo(StatusOfSalesOrderIsChangedTxt, Format(SalesHeader."No.")), Verbosity::Normal, DataClassification::CustomerContent, TelemetryScope::ExtensionPublisher, 'Category', UpdateSalesOrderStatusTxt);
        end;
    end;
    #endregion UpdatePendingPrepaymentSales

    #region GetPrepaymentInvoiceAccountNo
    procedure GetPrepaymentInvoiceAccountNo(CustomerOrderID: Code[20]): Code[20]
    var
        GenPostingSetup: Record "General Posting Setup";
        PostedSalesInvoiceHeader: Record "Sales Invoice Header";
        PostedSalesInvoiceLine: Record "Sales Invoice Line";
        CustomerOrderIdEmptyError: Label 'Customer Order Id must not be empty';
        PrepayAccountNotFoundError: Label 'Prepayment Invoice Posting Account was not found.';
        SalesPrepaymentsAccountEmptyError: Label 'Sales Prepayments Account is missing in General Posting Setup for %1, %2.';
    begin
        if CustomerOrderID = '' then
            exit(CustomerOrderIdEmptyError);

        PostedSalesInvoiceHeader.SetRange("LSC Customer Order ID", CustomerOrderID);
        PostedSalesInvoiceHeader.SetRange("Prepayment Invoice", true);
        if PostedSalesInvoiceHeader.FindLast() then begin
            PostedSalesInvoiceLine.SetRange("Document No.", PostedSalesInvoiceHeader."No.");
            if PostedSalesInvoiceLine.FindFirst() then begin
                GenPostingSetup.Get(PostedSalesInvoiceLine."Gen. Bus. Posting Group", PostedSalesInvoiceLine."Gen. Prod. Posting Group");
                if GenPostingSetup."Sales Prepayments Account" = '' then
                    Error(SalesPrepaymentsAccountEmptyError, PostedSalesInvoiceLine."Gen. Bus. Posting Group", PostedSalesInvoiceLine."Gen. Prod. Posting Group")
                else
                    exit(GenPostingSetup."Sales Prepayments Account");

            end;
        end;

        Error(PrepayAccountNotFoundError);
    end;
    #endregion GetPrepaymentInvoiceAccountNo    

    #region AfterCoEditOrderUpdatePaymentCheckPrepayment
    local procedure AfterCoEditOrderUpdatePaymentCheckPrepayment(var CustomerOrderHeader: Record "LSC Customer Order Header"; var CustomerOrderLineTemp: Record "LSC Customer Order Line" temporary; var SalesOrderPrepaymentToBeRecalculatedGlobal: Record "Sales Header" temporary)
    var
        CustomerOrderLine: Record "LSC Customer Order Line";
        EffectedSalesHeadersTemp: Record "Sales Header" temporary;
        SalesHeader: Record "Sales Header";
        CustomerOrderLineQtyCanceled: Decimal;
        CustomerOrderLineTempQtyCanceled: Decimal;
    begin
        if CustomerOrderHeader."Prepayment Invoice Type" <> Enum::"LSC Prepayment Invoice Type"::"Through Sales Order" then
            exit;
        CustomerOrderLineTemp.Reset();
        if CustomerOrderLineTemp.FindSet() then
            repeat
                CustomerOrderLineTempQtyCanceled := CustomerOrderLineTemp."Qty. Canceled in Collecting" + CustomerOrderLineTemp."Qty. Canceled in Picking";
                if CustomerOrderLine.Get(CustomerOrderLineTemp."Document ID", CustomerOrderLineTemp."Line No.") then begin
                    CustomerOrderLineQtyCanceled := CustomerOrderLine."Qty. Canceled in Collecting" + CustomerOrderLine."Qty. Canceled in Picking";

                    if (CustomerOrderLineTempQtyCanceled > CustomerOrderLineQtyCanceled) or (CustomerOrderLineTemp.Quantity < CustomerOrderLine.Quantity) then
                        if not EffectedSalesHeadersTemp.Get(CustomerOrderLine."Prepayment Document Type", CustomerOrderLine."Prepayment Document No.") then begin
                            Clear(EffectedSalesHeadersTemp);
                            EffectedSalesHeadersTemp."Document Type" := CustomerOrderLine."Prepayment Document Type";
                            EffectedSalesHeadersTemp."No." := CustomerOrderLine."Prepayment Document No.";
                            EffectedSalesHeadersTemp.Insert(false);
                        end;
                end;
            until CustomerOrderLineTemp.Next() = 0
        else begin
            // if the CustomerOrderLineTemp is empty then get all lines from the CustomerOrderHeader. This means that all lines has been canceled.
            // and then get all effected Sales Headers and create a Credit Memo for the Prepayment Invoice.
            CustomerOrderLine.SetRange("Document ID", CustomerOrderHeader."Document ID");
            if CustomerOrderLine.FindSet() then
                repeat
                    if not EffectedSalesHeadersTemp.Get(CustomerOrderLine."Prepayment Document Type", CustomerOrderLine."Prepayment Document No.") then begin
                        Clear(EffectedSalesHeadersTemp);
                        EffectedSalesHeadersTemp."Document Type" := CustomerOrderLine."Prepayment Document Type";
                        EffectedSalesHeadersTemp."No." := CustomerOrderLine."Prepayment Document No.";
                        EffectedSalesHeadersTemp.Insert(false);
                    end;
                until CustomerOrderLine.Next() = 0;
        end;

        Clear(EffectedSalesHeadersTemp);
        if EffectedSalesHeadersTemp.FindSet() then
            repeat
                if SalesHeader.Get(EffectedSalesHeadersTemp."Document Type", EffectedSalesHeadersTemp."No.") then begin
                    PopulateAndPostSalesCreditPrepaymentInvoice(CustomerOrderHeader, 0, SalesHeader);
                    SalesOrderPrepaymentToBeRecalculatedGlobal := SalesHeader;
                    SalesOrderPrepaymentToBeRecalculatedGlobal.Insert(false);
                end;
            until EffectedSalesHeadersTemp.Next() = 0;
    end;
    #endregion AfterCoEditOrderUpdatePaymentCheckPrepayment    

    #endregion Helpers and Common Functions

    #region Subscripers
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC CO Edit Order", 'OnAfterCoEditOrderUpdatePayment', '', false, false)]
    local procedure OnAfterCoEditOrderUpdatePaymentCheckPrepayment(CustomerOrderHeader: Record "LSC Customer Order Header"; var CustomerOrderPaymentTemp: Record "LSC Customer Order Payment" temporary; var CustomerOrderLineTemp: Record "LSC Customer Order Line" temporary; var NonExpiredCustomerOrderPaymentTemp: Record "LSC Customer Order Payment" temporary; var ErrorCode: Code[30]; var ErrorText: Text; var SalesOrderPrepaymentToBeRecalculatedGlobal: Record "Sales Header" temporary)
    begin
        AfterCoEditOrderUpdatePaymentCheckPrepayment(CustomerOrderHeader, CustomerOrderLineTemp, SalesOrderPrepaymentToBeRecalculatedGlobal);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC CO Utility", 'OnBeforeCancelSalesLineCheckPrePaymentForSalesLine', '', false, false)]
    local procedure OnBeforeCancelSalesLineCheckPrePaymentForSalesLine(CustomerOrderHeader: Record "LSC Customer Order Header"; var CustomerOrderLineTemp: Record "LSC Customer Order Line" temporary; var SalesLine: Record "Sales Line")
    begin
        SalesLine."Prepayment %" := 0;
        SalesLine."Prepmt. Amt. Inv." := 0;
        SalesLine."Prepmt. Amt. Incl. VAT" := 0;
        SalesLine."Prepayment Amount" := 0;
        SalesLine."Prepmt. VAT Base Amt." := 0;
        SalesLine."Prepayment VAT %" := 0;
        SalesLine."Prepmt. Amount Inv. Incl. VAT" := 0;
        SalesLine."Prepmt. Amount Inv. (LCY)" := 0;
        SalesLine."Prepmt. VAT Amount Inv. (LCY)" := 0;
        SalesLine."Prepmt. Pmt. Discount Amount" := 0;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post Prepayments", 'OnBeforeCheckOpenPrepaymentLines', '', false, false)]
    local procedure OnBeforeCheckOpenPrepaymentLinesForCreditPrepayment(SalesHeader: Record "Sales Header"; DocumentType: Option; var Found: Boolean; var IsHandled: Boolean)
    begin
        // if the Sales Header is a Credit Memo and then set Found to true and Ishandled to true.
        // this is in case that the Credit Memo is created from a Prepayment Invoice.
        // then skip the standard check for open prepayment lines.
        if (DocumentType <> 1) or // Credit Memo
            (SalesHeader."LSC Customer Order ID" = '')
        then
            exit;
        Found := true;
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnUpdateVATAmountsOnBeforeValidateLineDiscountPercent', '', false, false)]
    local procedure OnUpdateVATAmountsOnBeforeValidateLineDiscountPercentSuspendStatusCheck(var SalesLine: Record "Sales Line"; var StatusCheckSuspended: Boolean)
    begin
        if SalesLine."LSC Customer Order ID" <> '' then
            SalesLine.SuspendStatusCheck(StatusCheckSuspended);
    end;
    #endregion Subscripers
}
