table routable {
    reads {
     ethernet.sMac: exact;
     ethernet.dMac: exact;
     vlan_tag.vlan: exact;
    }
    actions {
     set_routable;
     set_mcast_pkt;
    }
    size : 64;
}

table unicast_routing {
    reads {
     ipv4.dip : ternary;
    }
    actions { 
     set_sMac;
     set_dMac;
     set_vlan;
    }
    size : 2000;
}

table multicast_routing {
    reads {
    ipv4.dip : ternary;
    }
    
    actions {
        set_mcast_idx;
    }
    size : 2000;
}


table mac_learning {
    reads { 
    	ethernet.sMac : exact;
	vlan_tag.vlan : exact;
    }
    actions {
      nop;
    }
    size : 64;
}

table igmp {
    reads {
        ipv4.dip: ternary;
    	vlan_tag.vlan: exact;
	meta.ig_port: exact;
    }
    actions {
      set_mcast_idx;
    }
    size : 500;
}

table switching {
    reads {
     ethernet.dMac : exact;
     vlan_tag.vlan : exact;
    }
    actions {
     set_egress;
    }
    size : 4000;
}

table acl {
    reads {
     ethernet.dMac : exact;
    }
    actions {
     set_drop_code;
    }
    size : 1000
}
