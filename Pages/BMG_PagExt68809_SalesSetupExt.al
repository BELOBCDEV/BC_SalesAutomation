pageextension 68809 BMGSalesSetupExt extends "Sales & Receivables Setup"
{
    layout
    {
        // Add changes to page layout here
        addlast(content)
        {
            group(MondayIntegration)
            {
                Caption = 'Monday.com Integration';

                field("API Key 2"; Rec."API Key 2")
                {
                    ApplicationArea = All;
                    Caption = 'API Key';
                }
                field("Corp IT Ticket Board ID"; Rec."Corp IT Ticket Board ID")
                {
                    ApplicationArea = All;
                }
                field("Cross-Dept Request Board ID"; Rec."Cross-Dept Request Board ID")
                {
                    ApplicationArea = All;
                }
                field("Enable Sending to Monday"; Rec."Enable Sending to Monday")
                {
                    ApplicationArea = All;
                }

            }
        }
    }

    actions
    {
        // Add changes to page actions here
    }

    var
        myInt: Integer;
}