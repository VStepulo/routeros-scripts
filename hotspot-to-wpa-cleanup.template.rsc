#!rsc by RouterOS
# RouterOS script: hotspot-to-wpa-cleanup%TEMPL%
# Copyright (c) 2021-2024 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# provides: lease-script, order=80
# requires RouterOS, version=7.14
#
# manage and clean up private WPA passphrase after hotspot login
# https://git.eworm.de/cgit/routeros-scripts/about/doc/hotspot-to-wpa.md
#
# !! This is just a template to generate the real script!
# !! Pattern '%TEMPL%' is replaced, paths are filtered.

:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:do {
  :local ScriptName [ :jobname ];

  :global EitherOr;
  :global LogPrint;
  :global ParseKeyValueStore;
  :global ScriptLock;

  :if ([ $ScriptLock $ScriptName 10 ] = false) do={
    :error false;
  }

  :local DHCPServers ({});
  :foreach Server in=[ /ip/dhcp-server/find where comment~"hotspot-to-wpa" ] do={
    :local ServerVal [ /ip/dhcp-server/get $Server ]
    :local ServerInfo [ $ParseKeyValueStore ($ServerVal->"comment") ];
    :if (($ServerInfo->"hotspot-to-wpa") = "wpa") do={
      :set ($DHCPServers->($ServerVal->"name")) \
        [ :totime [ $EitherOr ($ServerInfo->"timeout") 4w ] ];
    }
  }

  :foreach Client in=[ /caps-man/registration-table/find where comment~"^hotspot-to-wpa:" ] do={
  :foreach Client in=[ /interface/wifi/registration-table/find where comment~"^hotspot-to-wpa:" ] do={
    :local ClientVal [ /caps-man/registration-table/get $Client ];
    :local ClientVal [ /interface/wifi/registration-table/get $Client ];
    :foreach Lease in=[ /ip/dhcp-server/lease/find where dynamic \
        mac-address=($ClientVal->"mac-address") ] do={
      :if (($DHCPServers->[ /ip/dhcp-server/lease/get $Lease server ]) > 0s) do={
        $LogPrint info $ScriptName ("Client with mac address " . ($ClientVal->"mac-address") . \
          " connected to WPA, making lease static.");
        /ip/dhcp-server/lease/make-static $Lease;
        /ip/dhcp-server/lease/set comment=($ClientVal->"comment") $Lease;
      }
    }
  }

  :foreach Client in=[ /caps-man/access-list/find where comment~"^hotspot-to-wpa:" \
  :foreach Client in=[ /interface/wifi/access-list/find where comment~"^hotspot-to-wpa:" \
      !(comment~[ /system/clock/get date ]) mac-address ] do={
    :local ClientVal [ /caps-man/access-list/get $Client ];
    :local ClientVal [ /interface/wifi/access-list/get $Client ];
    :if ([ :len [ /ip/dhcp-server/lease/find where !dynamic comment~"^hotspot-to-wpa:" \
         mac-address=($ClientVal->"mac-address") ] ] = 0) do={
      $LogPrint info $ScriptName ("Client with mac address " . ($ClientVal->"mac-address") . \
        " did not connect to WPA, removing from access list.");
      /caps-man/access-list/remove $Client;
      /interface/wifi/access-list/remove $Client;
    }
  }

  :foreach Server,Timeout in=$DHCPServers do={
    :foreach Lease in=[ /ip/dhcp-server/lease/find where !dynamic status="waiting" \
        server=$Server last-seen>($Timeout + [ /system/clock/get time ]) \
        comment~"^hotspot-to-wpa:" ] do={
      :local LeaseVal [ /ip/dhcp-server/lease/get $Lease ];
      $LogPrint info $ScriptName ("Client with mac address " . ($LeaseVal->"mac-address") . \
        " was not seen for " . $Timeout . ", removing.");
      /caps-man/access-list/remove [ find where comment~"^hotspot-to-wpa:" \
      /interface/wifi/access-list/remove [ find where comment~"^hotspot-to-wpa:" \
        mac-address=($LeaseVal->"mac-address") ];
      /ip/dhcp-server/lease/remove $Lease;
    }
  }
} on-error={ }
