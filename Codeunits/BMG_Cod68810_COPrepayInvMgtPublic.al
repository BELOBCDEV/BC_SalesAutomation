codeunit 68810 "BMG CO Prepay. Inv. Mgt Public"
{
    #region "Events"
    [IntegrationEvent(false, false)]
    internal procedure OnBeforeCreateAndPostPrePaymentInvoice(Rec: Record "LSC Customer Order Header"; var SalesHeader: Record "Sales Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnAfterCreatAndPostPrePaymentInvoice(Rec: Record "LSC Customer Order Header"; var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnBeforePostGLForPrePaymentInvoice(var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnBeforePostGLForPrePaymentInvoiceLine(var GenJnlLine: Record "Gen. Journal Line"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnBeforePostPrepaymentAgainstPrepaymentCreditInvoice(Rec: Record "LSC Customer Order Header"; var SalesHeader: Record "Sales Header"; CreditAmount: Decimal; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnAfterPostPrepaymentAgainstPrepaymentCreditInvoice(Rec: Record "LSC Customer Order Header"; var SalesHeader: Record "Sales Header"; CreditAmount: Decimal)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnBeforeGetPrepaymentInvoiceAccountNo(var CustomerGenProdPostingGroup: Code[20]; var PrepInvoiceSetupItem: Code[20]; var AccountNo: Code[20]; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnAfterGetPrepaymentInvoiceAccountNo(var CustomerGenProdPostingGroup: Code[20]; varPrepInvoiceSetupItem: Code[20]; var AccountNo: Code[20])
    begin
    end;
    #endregion "Events"
}
