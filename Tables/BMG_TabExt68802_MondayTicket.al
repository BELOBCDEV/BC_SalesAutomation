table 68802 BMGMondayTickets
{
    DataClassification = ToBeClassified;
    Permissions = tabledata 68802 = RIMD;
    LookupPageId = BMGMondayTicketList;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            DataClassification = SystemMetadata;
            AutoIncrement = true;
        }
        field(2; "BMG Subject"; Text[100])
        {
            DataClassification = CustomerContent;
        }
        field(3; "BMG Comment"; Text[2048])
        {
            DataClassification = CustomerContent;
        }
        field(4; "BMG Name"; Text[80])
        {
            DataClassification = CustomerContent;
        }
        field(5; "Type of Request"; Option)
        {
            DataClassification = CustomerContent;
            OptionMembers = " ",Request,Incident;
            OptionCaption = ' ,Request,Incident';
        }
        field(6; "BMG Assignee"; Text[100])
        {
            DataClassification = CustomerContent;
        }
        field(7; "BMG Category"; Text[100])
        {
            DataClassification = CustomerContent;
        }
        field(8; "BMG Priority"; Option)
        {
            DataClassification = CustomerContent;
            OptionMembers = " ",High,Medium,Low,Critical;
            OptionCaption = ' ,High,Medium,Low,Critical';
        }
        field(9; "BMG Location"; Enum BMGMondayLocations)
        {
            DataClassification = CustomerContent;
        }
        field(10; "BMG Description"; Text[2048])
        {
            DataClassification = CustomerContent;
        }
        field(11; Files; Blob)
        {
            DataClassification = CustomerContent;
        }
        field(12; "BMG Requestor Email"; Text[80])
        {
            DataClassification = CustomerContent;
        }
        field(13; "BMG Ticket ID"; Text[50])
        {
            DataClassification = CustomerContent;
        }
        field(14; "BMG Status"; Text[100])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(15; "BMG Monday Item ID"; Text[50])
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(16; "BMG Assignee User"; Enum BMGMondayAssignees)
        {
            DataClassification = CustomerContent;

            trigger OnValidate()
            begin
                case Rec."BMG Assignee User" of
                    Enum::BMGMondayAssignees::jtenoso:
                        Rec."BMG Assignee ID" := '100753536';
                    Enum::BMGMondayAssignees::"Marlon Rubir":
                        Rec."BMG Assignee ID" := '100753534';
                    Enum::BMGMondayAssignees::"Rommel Marquez":
                        Rec."BMG Assignee ID" := '98458747';
                    Enum::BMGMondayAssignees::tfernandez:
                        Rec."BMG Assignee ID" := '100753541';
                    Enum::BMGMondayAssignees::"Victor Michael Buenavista":
                        Rec."BMG Assignee ID" := '95633921';
                    Enum::BMGMondayAssignees::"Trina Aquino":
                        Rec."BMG Assignee ID" := '100473531';
                    else
                        Rec."BMG Assignee ID" := '';
                end;
            end;
        }
        field(17; "BMG Assignee ID"; Text[50])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(18; "Date Submitted"; DateTime)
        {
            DataClassification = CustomerContent;
            Editable = false;
        }


    }

    keys
    {
        key(Key1; "Entry No.")
        {
            Clustered = true;
        }
    }

    fieldgroups
    {
    }

    trigger OnInsert()
    var
        recUser: Record User;
    begin
        recUser.Reset();
        recUser.SetRange("User Name", UserId);

        if recUser.FindFirst() then begin
            Rec."BMG Name" := recUser."Full Name";
            Rec."BMG Requestor Email" := recUser."Contact Email";
        end;

    end;

    trigger OnModify()
    begin
    end;

    trigger OnDelete()
    begin
    end;

    trigger OnRename()
    begin
    end;

}
