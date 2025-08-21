import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:first_flutter_app/data/item_data.dart';
import 'package:first_flutter_app/data/user.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'chat_page1.dart';

class ItemPage extends StatefulWidget {
  final ItemData selectedPost;

  const ItemPage({super.key, required this.selectedPost});

  @override
  State<StatefulWidget> createState() {
    return _ItemPage();
  }
}

class _ItemPage extends State<ItemPage> {
  ChatUser user = Get.find();
  QuerySnapshot<Map<String, dynamic>>? items ;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectedPost.title),
      ),
      body: SingleChildScrollView(child: Column(
        children: [
          Container(
            margin: EdgeInsets.all(10),
            padding: EdgeInsets.all(10),
            width: MediaQuery.of(context).size.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.selectedPost.image != ''
                    ? SizedBox(
                  height: (MediaQuery.of(context).size.height/3),
                  width: MediaQuery.of(context).size.width,
                  child:
                  Hero(tag: widget.selectedPost.timestamp, child: Image.network(widget.selectedPost.image ,fit: BoxFit.cover,)),
                )
                    : Container(),
                SizedBox(height: 10,),
                Text(widget.selectedPost.content , style: TextStyle(fontSize: 20)),
                SizedBox(height: 10,),
                Text('${widget.selectedPost.price}' , style: TextStyle(fontSize: 18),),
                SizedBox(height: 10,),
                Text(widget.selectedPost.user , style: TextStyle(fontSize: 12),),
                SizedBox(height: 10,),
                Text(widget.selectedPost.timestamp
                    .toDate()
                    .toString()
                    .substring(0, 16), style: TextStyle(fontSize: 10),),
                SizedBox(height: 10,),

              ],
            ),
          ),
          SizedBox(height: 50,),
          ElevatedButton(
            onPressed: () async {
              Get.to(ChatPage(selectedPost: widget.selectedPost));
            },
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.deepPurpleAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            child: Text(user.email == widget.selectedPost.user? '나에게 온 대화보기' :  '말걸어보기'),
          ),
          SizedBox(height: 20,),
        ],
      ),),
    );
  }
}
