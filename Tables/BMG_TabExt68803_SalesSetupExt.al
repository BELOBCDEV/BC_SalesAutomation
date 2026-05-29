tableextension 68803 BMGSalesSetup extends "Sales & Receivables Setup"
{
    fields
    {
        field(68800; "API Key 2"; Text[250])
        {
            DataClassification = CustomerContent;
        }
        field(68801; "Corp IT Ticket Board ID"; Text[50])
        {
            DataClassification = CustomerContent;
        }
        field(68802; "Enable Sending to Monday"; Boolean)
        {
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        // Add changes to keys here
    }

    fieldgroups
    {
        // Add changes to field groups here
    }

    var
        myInt: Integer;
}