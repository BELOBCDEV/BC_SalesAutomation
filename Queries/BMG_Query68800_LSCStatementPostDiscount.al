query 68800 "BMG Statement Post Discounts"
{
    Access = Internal;
    QueryType = Normal;

    elements
    {
        dataitem(TransactionStatus; "LSC Transaction Status")
        {
            filter(StatementNo; "Statement No.") { }

            dataitem(TransSalesEntry; "LSC Trans. Sales Entry")
            {
                DataItemLink = "Store No." = TransactionStatus."Store No.",
                             "POS Terminal No." = TransactionStatus."POS Terminal No.",
                             "Transaction No." = TransactionStatus."Transaction No.";

                dataitem(TransDiscountEntry; "LSC Trans. Discount Entry")
                {
                    DataItemLink = "Store No." = TransSalesEntry."Store No.",
                             "POS Terminal No." = TransSalesEntry."POS Terminal No.",
                             "Transaction No." = TransSalesEntry."Transaction No.",
                             "Line No." = TransSalesEntry."Line No.";
                    DataItemTableFilter = "Discount Amount" = filter(<> 0);
                    SqlJoinType = InnerJoin;

                    column(StoreNo; "Store No.")
                    {
                        Caption = 'Store No.';
                    }
                    column(POSTerminalNo; "POS Terminal No.")
                    {
                        Caption = 'POS Terminal No.';
                    }
                    column(TransactionNo; "Transaction No.")
                    {
                        Caption = 'Transaction No.';
                    }
                    column(LineNo; "Line No.")
                    {
                        Caption = 'Line No.';
                    }
                    column(OfferType; "Offer Type")
                    {
                        Caption = 'Offer Type';
                    }
                    column(DiscountAmount; "Discount Amount")
                    {
                        Caption = 'Discount Amount';
                        Method = Sum;
                    }
                }
            }
        }
    }
}