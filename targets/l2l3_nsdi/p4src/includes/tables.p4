
table routable {
    reads {
     ethernet.srcAddr: exact;
     ethernet.dstAddr: exact;
     vlan_tag_[0].vid: exact;
    }
    actions {
     set_routable;
     set_mcast_pkt;
    }
    size : 64;
}

action set_routable(val) {
    modify_field(ingress_metadata.is_routable, val);
}

action set_mcast_pkt(val) {
    modify_field(ingress_metadata.is_multicast, val);
}


table unicast_routing {
    reads {
     ipv4.dstAddr : ternary;
    }
    actions { 
     rewrite_unicast_mac;
     set_vlan;
    }
    size : 2000;
}

action rewrite_unicast_mac(smac, dmac) {
    modify_field(ethernet.srcAddr, smac);
    modify_field(ethernet.srcAddr, dmac);
}

action set_vlan(vlan_id) {
    modify_field(vlan_tag_[0].vid, vlan_id);
}

table multicast_routing {
    reads {
    ipv4.dstAddr : ternary;
    }
    
    actions {
        set_mcast_idx;
    }
    size : 2000;
}

action set_mcast_idx(idx) {
    modify_field(ingress_metadata.mc_idx, idx);
}

table mac_learning {
    reads { 
    	ethernet.srcAddr : exact;
	vlan_tag_[0].vid: exact;	
    }
    actions {
      nop;
    }
    size : 64;
}

action nop() {
}
table igmp {
    reads {
        ipv4.dstAddr: ternary;
	vlan_tag_[0].vid: exact;
        standard_metadata.ingress_port : exact;
    }
    actions {
      set_mcast_idx;
    }
    size : 500;
}

table switching {
    reads {
     ethernet.dstAddr : exact;
     vlan_tag_[0].vid: exact;	
    }
    actions {
     set_egress;
    }
    size : 4000;
}

action set_egress(port) {
    modify_field(standard_metadata.egress_spec, port);
}

table acl {
    reads {
     ethernet.srcAddr : exact;
     ethernet.dstAddr : exact;
     vlan_tag_[0].vid: exact;
     standard_metadata.ingress_port : exact;
    }
    actions {
     set_drop_code;
    }
    size : 1000;
}

action set_drop_code(code) {
    modify_field(ingress_metadata.drop_code, code);
}
